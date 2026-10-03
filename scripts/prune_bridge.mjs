// Follow Dart source directives from the bridge entry point. Dry run by default.
// --apply removes only unreachable lib files and tests importing removed sources.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = fs.realpathSync(process.cwd());
const local = p => path.resolve(root, p);
const normalize = p => path.relative(root, p).split(path.sep).join('/');
function files(dir) {
  if (!fs.existsSync(local(dir))) return [];
  return fs.readdirSync(local(dir), {withFileTypes: true}).flatMap(entry => {
    const name = `${dir}/${entry.name}`;
    return entry.isDirectory() ? files(name) : [name];
  });
}
function references(file) {
  const source = fs.readFileSync(local(file), 'utf8');
  return [...source.matchAll(/^\s*(?:import|export|part)\s+['"]([^'"]+)['"]/gm)]
    .map(([, uri]) => {
      if (uri.startsWith('package:openstrap_edge/')) return `lib/${uri.slice(23)}`;
      if (uri.includes(':')) return null;
      return normalize(path.resolve(path.dirname(local(file)), uri));
    }).filter(Boolean);
}
function closure(roots) {
  const reached = new Set();
  function visit(file) {
    if (reached.has(file)) return;
    assert(fs.existsSync(local(file)), `Missing dependency: ${file}`);
    reached.add(file);
    references(file).forEach(visit);
  }
  roots.forEach(visit);
  return reached;
}
const reached = closure(['lib/main.dart']);
const removed = files('lib').filter(f => f.endsWith('.dart') && !reached.has(f));
const removedSet = new Set(removed);
const tests = files('test').filter(f => f.endsWith('_test.dart'));
const retiredTests = tests.filter(f => {
  // Feature tests whose source tree is gone have no behavior left to verify.
  return [...closure([f])].some(source => removedSet.has(source));
});
const packages = new Set();
for (const file of reached) {
  const source = fs.readFileSync(local(file), 'utf8');
  for (const [, name] of source.matchAll(/['"]package:([^/]+)\//g)) packages.add(name);
}
console.log(JSON.stringify({retainedFiles: reached.size, removedFiles: removed.length,
  retiredTests: retiredTests.length, packages: [...packages].sort()}, null, 2));
fs.mkdirSync(local('.unlazy/whoop4'), {recursive: true});
fs.writeFileSync(local('.unlazy/whoop4/prune-inventory.json'), JSON.stringify({
  retained: [...reached].sort(), removed, retiredTests,
}, null, 2));
if (process.argv.includes('--apply')) {
  for (const file of [...removed, ...retiredTests]) {
    const target = local(file);
    assert(target.startsWith(root + path.sep), `Refusing out-of-workspace path: ${target}`);
    fs.unlinkSync(target);
  }
  console.log('Bridge pruning complete.');
}
