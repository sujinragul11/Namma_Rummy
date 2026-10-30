// Moves the game's database from Render to Neon: copies everything with pg_dump/pg_restore,
// checks that every row arrived unchanged, then runs migrate.js on Neon. Run it on this PC,
// from the backend folder, with the game server suspended on Render so nothing changes
// during the copy:
//
//   node src/database/move-to-neon.js            copy, check, migrate
//   node src/database/move-to-neon.js --check    compare the two databases again, change nothing
//
// The two addresses come from backend/.env.neon (another file can be named after the options).
// Render's database is only read, never changed. The copy goes in as one transaction, so a copy
// that fails leaves Neon empty. A backup of Render is kept in BACKUP_DIR.
const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const { spawn, execFileSync } = require('child_process');
const dotenv = require('dotenv');
const { Client } = require('pg');

const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const envFile = path.resolve(args.find((arg) => !arg.startsWith('--')) || path.join(__dirname, '../../.env.neon'));

const stop = (message) => {
  throw new Error(message);
};

// A database reached over the internet wants SSL; one on this machine does not (as in db.js)
const isRemote = (host) => host.includes('.') && host !== 'localhost' && !/^[0-9.]+$/.test(host);

const readUrl = (settings, name) => {
  const value = (settings[name] || '').trim();
  if (!value) stop(`${name} is empty in ${envFile}.`);
  let url;
  try {
    url = new URL(value);
  } catch (error) {
    stop(`${name} in ${envFile} is not a database address.`);
  }
  if (!/^postgres(ql)?:$/.test(url.protocol)) stop(`${name} must start with postgresql://`);
  return url;
};

// Host and database name, for messages: never the password
const describe = (url) => `${url.hostname}${url.pathname}`;

// The address without its SSL settings: in pg they would override the ssl option below and
// print warnings, so the code decides, the same way db.js does
const withoutSsl = (url) => {
  const plain = new URL(url);
  ['sslmode', 'channel_binding', 'uselibpqcompat', 'sslrootcert'].forEach((key) => plain.searchParams.delete(key));
  return plain.toString();
};

const connect = async (url) => {
  const client = new Client({
    connectionString: withoutSsl(url),
    ssl: isRemote(url.hostname) ? { rejectUnauthorized: false } : false,
  });
  await client.connect();
  // Dates, numbers and bytes as text the same way on both servers, for the comparison
  await client.query(
    `SET TimeZone = 'UTC'; SET DateStyle = 'ISO, MDY'; SET IntervalStyle = 'postgres';
     SET extra_float_digits = 1; SET bytea_output = 'hex'`
  );
  return client;
};

// pg_dump and pg_restore get the password through the environment, not on the command line
// where any program on this PC could read it
const toolTarget = (url) => {
  const plain = new URL(url);
  const password = decodeURIComponent(plain.password);
  plain.password = '';
  // verify-full needs a certificate file that libpq on Windows does not have; require still encrypts
  if (plain.searchParams.get('sslmode') === 'verify-full') plain.searchParams.set('sslmode', 'require');
  return { dbname: plain.toString(), env: { PGPASSWORD: password } };
};

const toolPath = (pgBin, name) => {
  const file = path.join(pgBin, process.platform === 'win32' ? `${name}.exe` : name);
  if (!fs.existsSync(file)) stop(`${file} not found. Set PG_BIN in ${envFile} to PostgreSQL's bin folder.`);
  return file;
};

const toolMajor = (file) => Number((execFileSync(file, ['--version']).toString().match(/(\d+)\.\d+/) || [])[1]);

const run = (file, toolArgs, env = {}) =>
  new Promise((resolve, reject) => {
    const child = spawn(file, toolArgs, { stdio: 'inherit', env: { ...process.env, ...env } });
    child.on('error', reject);
    child.on('exit', (code) =>
      code === 0 ? resolve() : reject(new Error(`${path.basename(file)} stopped with exit code ${code}.`))
    );
  });

const ask = (question) =>
  new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    let answer = '';
    rl.question(question, (text) => {
      answer = text.trim();
      rl.close();
    });
    rl.on('close', () => resolve(answer));
  });

const majorVersion = async (client) =>
  Math.floor(Number((await client.query('SHOW server_version_num')).rows[0].server_version_num) / 10000);

const quote = (name) => `"${name.replace(/"/g, '""')}"`;

// Every table and its columns, as Render has them
const listTables = async (client) =>
  (
    await client.query(`
      SELECT c.relname AS name, array_agg(a.attname::text ORDER BY a.attnum) AS columns
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
       WHERE n.nspname = 'public' AND c.relkind = 'r'
       GROUP BY c.relname
       ORDER BY c.relname`)
  ).rows;

// The number of rows and one hash over all of them. Only Render's columns count, so a column
// migrate.js adds on Neon afterwards does not make the tables look different
const fingerprint = async (client, table) => {
  const row = `ROW(${table.columns.map(quote).join(', ')})::text`;
  const { rows } = await client.query(
    `SELECT count(*)::int AS rows, coalesce(md5(string_agg(h, '' ORDER BY h)), '') AS hash
       FROM (SELECT md5(${row}) AS h FROM ${quote(table.name)}) AS t`
  );
  return rows[0];
};

const sequences = async (client) => {
  const { rows } = await client.query(
    `SELECT sequencename AS name, last_value::text AS value FROM pg_sequences WHERE schemaname = 'public'`
  );
  return new Map(rows.map((row) => [row.name, row.value]));
};

// Compares every table and sequence; returns what differs (nothing when Neon is a true copy)
const compare = async (render, neon) => {
  const problems = [];
  let total = 0;
  for (const table of await listTables(render)) {
    const before = await fingerprint(render, table);
    total += before.rows;
    let after;
    try {
      after = await fingerprint(neon, table);
    } catch (error) {
      console.log(`  ❌ ${table.name}: ${error.message}`);
      problems.push(`${table.name}: ${error.message}`);
      continue;
    }
    const same = before.rows === after.rows && before.hash === after.hash;
    console.log(
      `  ${same ? '✅' : '❌'} ${table.name.padEnd(22)} ${String(before.rows).padStart(8)} rows on Render` +
        `${same ? '' : `, ${after.rows} on Neon${before.rows === after.rows ? ' (contents differ)' : ''}`}`
    );
    if (!same) problems.push(`${table.name} differs`);
  }

  // The next id each table hands out; a copy that started them over would clash with old rows
  const renderSequences = await sequences(render);
  const neonSequences = await sequences(neon);
  for (const [name, value] of renderSequences) {
    if (neonSequences.get(name) !== value) {
      problems.push(`sequence ${name} is at ${value} on Render, ${neonSequences.get(name)} on Neon`);
    }
  }
  console.log(`  ${problems.length ? '❌' : '✅'} ${renderSequences.size} id counters, ${total} rows in all`);
  return problems;
};

// Other connections of the game's database user: the game server, or a database tool left open
const otherConnections = async (client) =>
  (
    await client.query(
      `SELECT coalesce(nullif(application_name, ''), 'no name') AS app, state, client_addr::text AS addr
         FROM pg_stat_activity
        WHERE datname = current_database() AND pid <> pg_backend_pid() AND usename = current_user`
    )
  ).rows;

// What Neon already holds: tables, views and id counters. Tables are named first
const objectsIn = async (client) =>
  (
    await client.query(
      `SELECT c.relname AS name FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm', 'S', 'p') ORDER BY c.relkind <> 'r', 1`
    )
  ).rows.map((row) => row.name);

const migrate = (neonUrl) =>
  run(process.execPath, [path.join(__dirname, 'migrate.js')], {
    DATABASE_URL: withoutSsl(neonUrl),
    PGSSL: isRemote(neonUrl.hostname) ? '1' : '0',
  });

const main = async () => {
  if (!fs.existsSync(envFile)) stop(`${envFile} not found. Fill in backend/.env.neon first.`);
  const settings = dotenv.parse(fs.readFileSync(envFile));
  const renderUrl = readUrl(settings, 'RENDER_DATABASE_URL');
  const neonUrl = readUrl(settings, 'NEON_DATABASE_URL');

  if (describe(renderUrl) === describe(neonUrl)) stop('RENDER_DATABASE_URL and NEON_DATABASE_URL are the same database.');
  if (renderUrl.hostname.endsWith('neon.tech')) stop('RENDER_DATABASE_URL is a Neon address. Are the two swapped?');
  if (!renderUrl.hostname.includes('.') && renderUrl.hostname !== 'localhost') {
    stop("RENDER_DATABASE_URL is Render's Internal URL, which works only inside Render. Use the External Database URL.");
  }
  if (neonUrl.hostname.includes('-pooler')) {
    stop('NEON_DATABASE_URL goes through the connection pooler. In Neon > Connect, switch "Connection pooling" off and copy it again.');
  }

  console.log(`From Render: ${describe(renderUrl)}`);
  console.log(`To Neon:     ${describe(neonUrl)}\n`);

  const render = await connect(renderUrl);
  const neon = await connect(neonUrl);
  try {
    // Belt and braces: this session could not change Render's data even by mistake
    await render.query('SET default_transaction_read_only = on');

    const connections = await otherConnections(render);
    if (connections.length) {
      console.log(`⚠️  ${connections.length} other connection(s) to the Render database:`);
      connections.forEach((c) => console.log(`     ${c.app}, ${c.state || 'unknown'}, from ${c.addr || 'inside Render'}`));
    }

    if (checkOnly) {
      console.log('Comparing Render and Neon:');
      const problems = await compare(render, neon);
      if (problems.length) stop(`Neon is not the same as Render:\n  - ${problems.join('\n  - ')}`);
      console.log('\n✅ Neon holds exactly what Render holds.');
      return;
    }

    if (connections.length) {
      stop(
        'Something is still connected to the Render database, so it could change during the copy.\n' +
          'Suspend the game server on Render (and close any database tool), wait a minute, then run this again.'
      );
    }

    const renderMajor = await majorVersion(render);
    const neonMajor = await majorVersion(neon);
    const pgBin = (settings.PG_BIN || '').trim() || 'C:\\Program Files\\PostgreSQL\\17\\bin';
    const pgDump = toolPath(pgBin, 'pg_dump');
    const pgRestore = toolPath(pgBin, 'pg_restore');
    const dumpMajor = toolMajor(pgDump);
    if (dumpMajor < renderMajor) stop(`Render runs PostgreSQL ${renderMajor}; pg_dump ${dumpMajor} cannot copy it. Install PostgreSQL ${renderMajor} tools.`);
    if (neonMajor < renderMajor) stop(`Neon runs PostgreSQL ${neonMajor}, older than Render's ${renderMajor}. Make the Neon project with ${renderMajor} or newer.`);

    const already = await objectsIn(neon);
    if (already.length) {
      const shown = already.slice(0, 6).join(', ') + (already.length > 6 ? ` and ${already.length - 6} more` : '');
      stop(
        `Neon already has tables (${shown}), so nothing was copied.\n` +
          'If they are from an earlier run and the game is NOT using Neon yet, empty it in Neon > SQL Editor with\n' +
          '  DROP SCHEMA public CASCADE; CREATE SCHEMA public;\n' +
          'and run this again. If the game already runs on Neon, those tables hold new games and accounts: leave them.'
      );
    }

    const size = Number((await render.query('SELECT pg_database_size(current_database()) AS size')).rows[0].size);
    console.log(`Render: PostgreSQL ${renderMajor}, ${(size / 1024 / 1024).toFixed(1)} MB. Neon: PostgreSQL ${neonMajor}, empty.`);
    console.log(`pg_dump and pg_restore ${dumpMajor} from ${pgBin}\n`);

    const answer = await ask('Is the game server SUSPENDED on Render? Type YES to start the copy: ');
    if (answer !== 'YES') stop('Nothing was copied.');

    const backupDir = (settings.BACKUP_DIR || '').trim() || path.join(os.homedir(), 'namma-rummy-backups');
    fs.mkdirSync(backupDir, { recursive: true });
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const dumpFile = path.join(
      backupDir,
      `render-${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}.dump`
    );

    console.log('\n1/4 Copying Render to a backup file...');
    const from = toolTarget(renderUrl);
    await run(
      pgDump,
      ['--format=custom', '--no-owner', '--no-acl', '--no-publications', '--no-subscriptions',
        '--no-security-labels', '--no-tablespaces', `--file=${dumpFile}`, `--dbname=${from.dbname}`],
      from.env
    );
    console.log(`    ✅ ${dumpFile} (${(fs.statSync(dumpFile).size / 1024 / 1024).toFixed(1)} MB)`);

    console.log('2/4 Loading it into Neon, all or nothing...');
    const to = toolTarget(neonUrl);
    await run(pgRestore, ['--single-transaction', '--exit-on-error', '--no-owner', '--no-acl', `--dbname=${to.dbname}`, dumpFile], to.env);
    console.log('    ✅ loaded');

    console.log('3/4 Comparing every table, row by row:');
    let problems = await compare(render, neon);
    if (problems.length) {
      stop(`Neon is not the same as Render. Do NOT switch the game to Neon:\n  - ${problems.join('\n  - ')}`);
    }

    console.log('4/4 Running migrate.js on Neon...');
    await migrate(neonUrl);
    console.log('    Comparing again after the migration:');
    problems = await compare(render, neon);
    if (problems.length) stop(`The migration changed data on Neon. Do NOT switch the game to Neon:\n  - ${problems.join('\n  - ')}`);

    console.log(
      `\n✅ Done. Neon holds every row of Render, and its tables are up to date.\n` +
        `   Backup of Render: ${dumpFile}\n` +
        '   Next: put NEON_DATABASE_URL into DATABASE_URL on the Render service, then resume it.'
    );
  } finally {
    await Promise.all([render.end(), neon.end()]);
  }
};

main().catch((error) => {
  console.error(`\n❌ ${error.message}`);
  process.exitCode = 1;
});
