// The chat messages players have reported, for the game's team to look at. Each report holds
// the message, who wrote it and who reported it; the one who reported it has already blocked
// its sender. Run it where the server's database settings are (.env, or the host's environment):
//
//   npm run chat-reports                  the reports not looked at yet
//   npm run chat-reports -- --all         every report
//   npm run chat-reports -- --done <id>   marks a report as looked at
//
// An account that keeps being reported can have its logins ended (npm run revoke-logins) or
// be deleted.
const db = require('./db');
const ChatModeration = require('../models/ChatModeration');

const when = (time) => new Date(time).toISOString().slice(0, 16).replace('T', ' ');

const run = async () => {
  await ChatModeration.ensureSchema();
  const args = process.argv.slice(2);

  const done = args.indexOf('--done');
  if (done >= 0) {
    const id = Number(args[done + 1]);
    if (!Number.isInteger(id) || id <= 0) {
      console.error('Usage: npm run chat-reports -- --done <report number>');
      return 1;
    }
    const marked = await ChatModeration.markReviewed(id);
    console.log(marked ? `Report #${id} is marked as looked at.` : `No open report #${id}.`);
    return marked ? 0 : 1;
  }

  const all = args.includes('--all');
  const reports = await ChatModeration.reports({ all });
  if (reports.length === 0) {
    console.log(all ? 'No chat reports.' : 'No chat reports waiting.');
    return 0;
  }
  for (const report of reports) {
    const state = report.reviewed_at ? `looked at ${when(report.reviewed_at)}` : 'open';
    console.log(`#${report.id}  ${when(report.created_at)} UTC  (${state})`);
    console.log(`   written by  ${report.reported_name} (user ${report.reported_id}), reported ${report.times_reported} time(s) in all`);
    console.log(`   reported by ${report.reporter_name} (user ${report.reporter_id})`);
    console.log(`   message     ${report.message}`);
  }
  console.log(`\n${reports.length} report(s).${all ? '' : ' Mark one as looked at with: npm run chat-reports -- --done <number>'}`);
  return 0;
};

run()
  .then((code) => { process.exitCode = code; })
  .catch((error) => {
    console.error('Failed:', error.message);
    process.exitCode = 1;
  })
  .finally(() => db.pool.end());
