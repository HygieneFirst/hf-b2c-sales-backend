// Disposable, in-memory PostgreSQL verification. No hosted connections.
// Usage: node <this-file> <pglite-module-file> <controller-json> <controller-rpc-sql>
// Install @electric-sql/pglite@0.3.14 (PostgreSQL 17.5) in a temporary directory,
// outside the repository. Export the two source files from the controller ZIP.
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve, dirname } from 'node:path';

const [moduleFile, exportFile, rpcFile] = process.argv.slice(2);
assert(moduleFile && exportFile && rpcFile, 'Supply runtime module, controller JSON and RPC SQL');
const { PGlite } = await import(pathToFileURL(resolve(moduleFile)).href);
const source = JSON.parse(readFileSync(exportFile, 'utf8'));
const rpcSource = readFileSync(rpcFile, 'utf8').replace(/^\uFEFF/, '');
const migrations = resolve(dirname(fileURLToPath(import.meta.url)), '../migrations');
const db = new PGlite();
let passes = 0;
const pass = (name) => { passes++; console.log(`PASS ${name}`); };
const query = async (sql, params = []) => (await db.query(sql, params)).rows;

async function denied(role, sql) {
  await db.exec(`SET ROLE ${role}`);
  try {
    await assert.rejects(() => db.exec(sql), (error) => error.code === '42501');
  } finally {
    await db.exec('RESET ROLE');
  }
}

async function lookup(text, topic = null, limit = 3) {
  return (await query('SELECT public.b2c_kb_lookup_v1($1, $2, $3) AS result', [text, topic, limit]))[0].result;
}

try {
  console.log(JSON.stringify((await query('SELECT version(), current_user'))[0]));
  // Supabase normally provides these roles and auth.uid(). The stub is only
  // for baseline function dependencies; this test does not verify Supabase Auth.
  await db.exec(`
    CREATE ROLE anon NOLOGIN;
    CREATE ROLE authenticated NOLOGIN;
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
    CREATE SCHEMA auth;
    CREATE TABLE auth.users (id uuid PRIMARY KEY);
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS 'SELECT NULL::uuid';
    GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
  `);
  const files = readdirSync(migrations).filter(name => name.endsWith('.sql')).sort();
  for (const file of files) {
    await db.exec(readFileSync(resolve(migrations, file), 'utf8'));
    pass(`fresh migration ${file}`);
  }

  const versions = await query('SELECT * FROM public.b2c_kb_versions');
  assert.equal(versions.length, 1);
  const { created_at: versionCreated, ...version } = versions[0];
  assert(versionCreated);
  assert.equal(new Date(version.approved_at).toISOString(), new Date(source.version.approved_at).toISOString());
  version.approved_at = source.version.approved_at;
  assert.deepEqual(version, source.version);
  pass('exact approved version, including approval metadata');

  const rows = await query('SELECT * FROM public.b2c_kb_entries ORDER BY version_id, kb_fact_id');
  assert.equal(rows.length, 47);
  assert.equal(source.entry_count, 47);
  const withoutGenerated = rows.map(({ created_at, ...row }) => { assert(created_at); return row; });
  const orderedSource = [...source.entries].sort((a, b) => a.kb_fact_id < b.kb_fact_id ? -1 : a.kb_fact_id > b.kb_fact_id ? 1 : 0);
  assert.deepEqual(withoutGenerated, orderedSource);
  pass('47/47 rows exact across ALL exported fields and array order');
  const counts = Object.fromEntries((await query('SELECT service_topic, count(*)::int AS n FROM public.b2c_kb_entries GROUP BY service_topic')).map(row => [row.service_topic, row.n]));
  assert.deepEqual(counts, source.schema_contract.topic_counts);
  assert(rows.every(row => row.status === 'APPROVED'));
  pass('exact topic counts and approved status');

  for (const [table, spec] of Object.entries(source.schema_contract.tables)) {
    const columns = await query(`SELECT column_name, data_type, udt_name, is_nullable, column_default
      FROM information_schema.columns WHERE table_schema='public' AND table_name=$1 ORDER BY ordinal_position`, [table.split('.')[1]]);
    assert.deepEqual(columns.map(c => c.column_name), spec.columns.map(c => c.name));
    const types = { text: 'text', timestamptz: 'timestamptz', 'text[]': '_text', boolean: 'bool', integer: 'int4' };
    for (let i = 0; i < columns.length; i++) {
      assert.equal(columns[i].udt_name, types[spec.columns[i].type]);
      assert.equal(columns[i].is_nullable, spec.columns[i].nullable ? 'YES' : 'NO');
      if ('default' in spec.columns[i]) assert(columns[i].column_default);
      if (spec.columns[i].check) {
        const constraints = await query('SELECT pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid=$1::regclass AND contype=\'c\'', [table]);
        assert(constraints.some(c => spec.columns[i].check.every(value => c.definition.includes(`'${value}'`))));
      }
    }
    const relation = (await query('SELECT relrowsecurity FROM pg_class WHERE oid=$1::regclass', [table]))[0];
    assert.equal(relation.relrowsecurity, true);
    const keys = await query(`SELECT a.attname FROM pg_constraint c
      CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
      JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum
      WHERE c.conrelid=$1::regclass AND c.contype='p' ORDER BY k.ord`, [table]);
    assert.deepEqual(keys.map(k => k.attname), spec.primary_key);
    for (const role of ['anon', 'authenticated']) {
      await denied(role, `SELECT * FROM ${table}`);
      assert.equal((await query('SELECT has_table_privilege($1, $2, \'SELECT\') AS allowed', [role, table]))[0].allowed, false);
    }
    await db.exec('SET ROLE service_role');
    try { assert.equal((await query(`SELECT count(*)::int AS n FROM ${table}`))[0].n, spec.rows); }
    finally { await db.exec('RESET ROLE'); }
    pass(`${table}: column contract, PK, checks, RLS, denied anon/authenticated, service_role SELECT`);
  }
  const fk = await query(`SELECT pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid='public.b2c_kb_entries'::regclass AND contype='f'`);
  assert(fk.some(row => /FOREIGN KEY \(version_id\) REFERENCES (public\.)?b2c_kb_versions\(version_id\)/.test(row.definition)));
  const index = (await query(`SELECT indexdef FROM pg_indexes WHERE schemaname='public' AND indexname='b2c_kb_entries_version_service_idx'`))[0];
  assert(index.indexdef.includes('(version_id, service_topic, status)'));
  pass('version FK and known retrieval index');

  const fn = (await query(`SELECT prosrc, prosecdef, proconfig, pg_get_userbyid(proowner) AS owner
    FROM pg_proc WHERE oid='public.b2c_kb_lookup_v1(text,text,integer)'::regprocedure`))[0];
  assert.equal(fn.prosrc, rpcSource.split('$function$')[1]);
  assert.equal(fn.prosecdef, true);
  assert.equal(fn.owner, 'postgres');
  assert(fn.proconfig.includes('search_path=public, pg_temp'));
  for (const role of ['anon', 'authenticated']) await denied(role, "SELECT public.b2c_kb_lookup_v1('有咩服務')");
  for (const role of ['postgres', 'service_role']) {
    assert.equal((await query(`SELECT has_function_privilege($1, 'public.b2c_kb_lookup_v1(text,text,integer)', 'EXECUTE') AS allowed`, [role]))[0].allowed, true);
  }
  pass('exact live RPC body, owner, SECURITY DEFINER, search_path and EXECUTE privileges');
  await db.exec('SET ROLE service_role');
  try {
    const supported = await lookup('有咩服務');
    assert.equal(supported.retrieval_status, 'MATCH');
    assert.equal(supported.matches[0].kb_fact_id, 'KB-CATALOGUE');
    pass('service_role supported query retrieves correct fact');
    for (const topic of [null, ...Object.keys(source.schema_contract.topic_counts)]) {
      const unknown = await lookup('量子火箭燃料abcdef', topic);
      assert.equal(unknown.retrieval_status, 'NO_AUTHORITATIVE_ANSWER');
      assert.deepEqual(unknown.matches, []);
    }
    pass('unsupported query fails closed with and without every service-topic hint');
    for (const [text, topic, expected] of [['幾錢', null, 'PRICE_HUMAN'], ['今日有冇位', null, 'LIVE_CONFIRMATION'], ['remove stitches', 'wound_care', 'CLINICAL_HUMAN']]) {
      const result = await lookup(text, topic);
      assert.equal(result.retrieval_status, 'MATCH');
      assert.equal(result.matches[0].response_class, expected);
      pass(`${text} -> ${expected}`);
    }
    for (const text of [null, '', '   ']) assert.equal((await lookup(text)).reason, 'EMPTY_QUERY');
    pass('empty/null input fails closed');
    for (const limit of [null, 0, 6]) assert.deepEqual(await lookup('送飯', 'meal_delivery', limit), await lookup('送飯', 'meal_delivery', 3));
    pass('invalid limit uses live default behavior');
  } finally { await db.exec('RESET ROLE'); }
  // Missing approval and withdrawn rows must not become authoritative.
  await db.exec('BEGIN; UPDATE public.b2c_kb_entries SET status=\'WITHDRAWN\'');
  assert.equal((await lookup('有咩服務')).retrieval_status, 'NO_AUTHORITATIVE_ANSWER');
  await db.exec('ROLLBACK; BEGIN; UPDATE public.b2c_kb_versions SET status=\'WITHDRAWN\'');
  assert.equal((await lookup('有咩服務')).reason, 'NO_APPROVED_KB_VERSION');
  await db.exec('ROLLBACK');
  pass('withdrawn entries and no approved version fail closed');
  console.log(`RESULT ${passes} checks passed; no live-system connection`);
} catch (error) {
  console.error(`FAIL ${error.code ?? error.name}: ${error.message}`);
  process.exitCode = 1;
} finally {
  await db.close();
}
