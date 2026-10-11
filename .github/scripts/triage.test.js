'use strict';

// Tests for triage.js. Run them with: node --test .github/scripts/triage.test.js
// The bodies are built the way GitHub writes a submitted issue form: a heading
// for each field, and a code fence around a field with render.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const triage = require('./triage.js');

const GOOD_VIMRC = 'set nocompatible\nset rtp+=/home/me/bartleby,/home/me/Logger\nfiletype plugin on';

function fence(text) {
  return '```vim\n' + text + '\n```';
}

// A bug report body. The fields are the ones that the script reads.
function bugBody({vimrc = fence(GOOD_VIMRC), component = 'Binder and the scrive tree', environment = 'Terminal Vim', extra = ''} = {}) {
  return `### Bartleby commit

3f2a9c1

### Where do you run Vim?

${environment}

### Component

${component}

### Describe the bug

It breaks.${extra}

### Minimal vimrc

${vimrc}

### Expected behavior

It works.
`;
}

function issue(labels, body) {
  return {number: 7, labels: labels.map((name) => ({name})), body};
}

// A stand-in for the GitHub API that records every call.
function fake({comments = [], failComment = false} = {}) {
  const calls = {createLabel: [], addLabels: [], removeLabel: [], createComment: []};
  const github = {
    paginate: async () => comments,
    rest: {
      issues: {
        listComments: () => {},
        createLabel: async (a) => { calls.createLabel.push(a.name); },
        addLabels: async (a) => { calls.addLabels.push(...a.labels); },
        removeLabel: async (a) => { calls.removeLabel.push(a.name); },
        createComment: async (a) => {
          if (failComment) {
            throw new Error('boom');
          }
          calls.createComment.push(a.body);
        },
      },
    },
  };
  const warnings = [];
  const core = {warning: (message) => warnings.push(message)};
  return {github, core, calls, warnings};
}

function context(theIssue, eventName = 'issues') {
  return {eventName, repo: {owner: 'o', repo: 'r'}, payload: {issue: theIssue}};
}

test('section reads a field, and treats No response as empty', () => {
  const body = bugBody();
  assert.equal(triage.section(body, 'Component'), 'Binder and the scrive tree');
  assert.equal(triage.section(body, 'Nothing here'), '');
  assert.equal(triage.section('### Minimal vimrc\n\n_No response_', 'Minimal vimrc'), '');
});

test('section keeps a multi-line field whole, up to the next heading', () => {
  assert.equal(triage.section(bugBody(), 'Minimal vimrc'), fence(GOOD_VIMRC));
});

test('a vimrc must load Bartleby and Logger', () => {
  assert.equal(triage.vimrcProblem(fence(GOOD_VIMRC)), '');
  assert.match(triage.vimrcProblem(fence('set nocp')), /does not load Bartleby/);
  assert.match(triage.vimrcProblem(fence('" nothing')), /is empty/);
  assert.match(triage.vimrcProblem(''), /is empty/);
  assert.match(triage.vimrcProblem(fence('set rtp+=/home/me/bartleby')), /does not load Logger/);
});

test('a comment, a Vim9 comment, and a fence are not settings', () => {
  const text = fence('" set rtp+=/bartleby,/Logger\n# set rtp+=/bartleby,/Logger\n\nset nocp');
  assert.match(triage.vimrcProblem(text), /does not load Bartleby/);
});

test('a plugin manager line that names both plugins is accepted', () => {
  const text = fence("call plug#begin()\nPlug 'Galvarcus/bartleby'\nPlug 'Galvarcus/Logger'\ncall plug#end()");
  assert.equal(triage.vimrcProblem(text), '');
});

test('a key is found, and a placeholder or an empty value is not', () => {
  assert.equal(triage.leaksKey('let g:bartleby_dictionary_api_key = "0a1b2c3d-4e5f-6789-abcd-ef0123456789"'), true);
  assert.equal(triage.leaksKey("let g:bartleby_thesaurus_api_key = 'abcdef123456'"), true);
  assert.equal(triage.leaksKey("let g:x['api_key'] = 'abcdef123456'"), true);
  assert.equal(triage.leaksKey('let g:bartleby_dictionary_api_key = "YOUR_KEY_HERE"'), false);
  assert.equal(triage.leaksKey('let g:bartleby_dictionary_api_key = ""'), false);
  assert.equal(triage.leaksKey('set an api_key somewhere'), false);
  assert.equal(triage.leaksKey(''), false);
});

test('a bug with a good vimrc gets only its component label', () => {
  const plan = triage.analyze(issue(['bug', 'needs-triage'], bugBody()));
  assert.deepEqual(plan.add, ['binder']);
  assert.deepEqual(plan.remove, []);
  assert.deepEqual(plan.comments, []);
});

test('a bug with a vimrc that does not load Bartleby gets needs-repro and one comment', () => {
  const plan = triage.analyze(issue(['bug'], bugBody({vimrc: fence('set nocp')})));
  assert.ok(plan.add.includes('needs-repro'));
  assert.equal(plan.comments.length, 1);
  assert.ok(plan.comments[0].text.includes(triage.MARKERS.repro));
});

test('only a bug report is asked for a vimrc', () => {
  const plan = triage.analyze(issue(['enhancement'], bugBody({vimrc: fence('set nocp')})));
  assert.ok(!plan.add.includes('needs-repro'));
  assert.equal(plan.comments.length, 0);
});

test('a GUI answer adds gui, and Terminal Vim does not', () => {
  assert.ok(triage.analyze(issue(['bug'], bugBody({environment: 'MacVim'}))).add.includes('gui'));
  assert.ok(triage.analyze(issue(['bug'], bugBody({environment: 'gVim'}))).add.includes('gui'));
  assert.ok(!triage.analyze(issue(['bug'], bugBody())).add.includes('gui'));
});

test('a key in any issue gets needs-redaction and one comment', () => {
  const body = 'Here is my vimrc:\nlet g:bartleby_dictionary_api_key = "0a1b2c3d-4e5f-6789-abcd-ef0123456789"';
  const plan = triage.analyze(issue(['enhancement'], body));
  assert.ok(plan.add.includes('needs-redaction'));
  assert.ok(plan.comments[0].text.includes(triage.MARKERS.secret));
});

test('a documentation typo gets good first issue, and another type does not', () => {
  const typo = '### Type of documentation issue\n\nTypo or grammatical error\n\n### Which document?\n\nREADME.md';
  const other = '### Type of documentation issue\n\nUnclear or confusing explanation';
  assert.ok(triage.analyze(issue(['documentation'], typo)).add.includes('good first issue'));
  assert.ok(!triage.analyze(issue(['documentation'], other)).add.includes('good first issue'));
  assert.ok(!triage.analyze(issue(['bug'], typo)).add.includes('good first issue'));
});

test('a fixed vimrc removes needs-repro, and a maintainer label stays', () => {
  const plan = triage.analyze(issue(['bug', 'needs-repro', 'help wanted'], bugBody()));
  assert.deepEqual(plan.remove, ['needs-repro']);
});

test('a removed key removes needs-redaction', () => {
  const plan = triage.analyze(issue(['bug', 'needs-redaction'], bugBody()));
  assert.deepEqual(plan.remove, ['needs-redaction']);
});

test('run labels, comments, and creates the missing labels', async () => {
  const {github, core, calls} = fake();
  await triage.run({github, core, context: context(issue(['bug'], bugBody({vimrc: fence('set nocp')})))});
  assert.deepEqual(calls.createLabel.sort(), ['binder', 'needs-repro']);
  assert.deepEqual(calls.addLabels.sort(), ['binder', 'needs-repro']);
  assert.equal(calls.createComment.length, 1);
});

test('run does not comment twice when its comment is already there', async () => {
  const {github, core, calls} = fake({comments: [{body: triage.MARKERS.repro + '\nold'}]});
  await triage.run({github, core, context: context(issue(['bug', 'needs-repro'], bugBody({vimrc: fence('set nocp')})), 'issues')});
  assert.equal(calls.createComment.length, 0);
});

test('run removes needs-repro after the vimrc is fixed', async () => {
  const {github, core, calls} = fake();
  await triage.run({github, core, context: context(issue(['bug', 'needs-repro', 'binder'], bugBody()))});
  assert.deepEqual(calls.removeLabel, ['needs-repro']);
  assert.deepEqual(calls.addLabels, []);
});

test('a failed comment does not stop the labels, and is reported', async () => {
  const {github, core, calls, warnings} = fake({failComment: true});
  await triage.run({github, core, context: context(issue(['bug'], bugBody({vimrc: fence('set nocp')})))});
  assert.ok(calls.addLabels.includes('needs-repro'));
  assert.ok(warnings.some((message) => message.includes('posting a comment failed')));
});

test('an existing label is not an error', async () => {
  const {github, core, calls, warnings} = fake();
  github.rest.issues.createLabel = async () => {
    const error = new Error('Validation Failed');
    error.status = 422;
    throw error;
  };
  await triage.run({github, core, context: context(issue(['bug'], bugBody()))});
  assert.deepEqual(calls.addLabels, ['binder']);
  assert.deepEqual(warnings, []);
});

test('a run by hand creates every label', async () => {
  const {github, core, calls} = fake();
  await triage.run({github, core, context: {eventName: 'workflow_dispatch', repo: {owner: 'o', repo: 'r'}, payload: {}}});
  assert.deepEqual(calls.createLabel.sort(), Object.keys(triage.LABELS).sort());
});

// ---- the script and the templates must agree -------------------------------

function template(file) {
  return fs.readFileSync(path.join(__dirname, '..', 'ISSUE_TEMPLATE', file), 'utf8');
}

// The answers of the dropdown with this id, from the text of a template.
function dropdownOptions(file, id) {
  const text = template(file);
  const start = text.indexOf(`id: ${id}\n`);
  assert.notEqual(start, -1, `${file} has no field ${id}`);
  const block = text.slice(start).split(/\n {2}- type:/)[0];
  const options = block.split('options:\n')[1] || '';
  return options.split('\n').filter((line) => /^ {8}- /.test(line)).map((line) => line.replace(/^ {8}- /, '').replace(/^"|"$/g, '').trim());
}

test('the bug report and the feature request offer exactly the component answers', () => {
  const expected = [...Object.keys(triage.COMPONENTS), 'Not sure'].sort();
  assert.deepEqual(dropdownOptions('bug_report.yml', 'component').sort(), expected);
  assert.deepEqual(dropdownOptions('feature_request.yml', 'component').sort(), expected);
});

test('the bug report offers every GUI answer that the script knows', () => {
  const options = dropdownOptions('bug_report.yml', 'environment');
  for (const name of triage.GUI_ENVIRONMENTS) {
    assert.ok(options.includes(name), `${name} is not a choice of the bug report`);
  }
  assert.ok(options.includes('Terminal Vim'));
});

test('the documentation form offers the typo answer that the script looks for', () => {
  assert.ok(dropdownOptions('documentation.yml', 'doc-type').includes('Typo or grammatical error'));
});

test('the headings that the script reads are the labels of the forms', () => {
  assert.match(template('bug_report.yml'), /label: Minimal vimrc\n/);
  assert.match(template('bug_report.yml'), /label: Where do you run Vim\?\n/);
  assert.match(template('bug_report.yml'), /label: Component\n/);
  assert.match(template('feature_request.yml'), /label: Component\n/);
  assert.match(template('documentation.yml'), /label: Type of documentation issue\n/);
});

test('every label that a template applies is one that the script creates', () => {
  for (const file of fs.readdirSync(path.join(__dirname, '..', 'ISSUE_TEMPLATE')).filter((name) => name !== 'config.yml')) {
    const match = template(file).match(/^labels: \[(.*)\]$/m);
    assert.ok(match, `${file} has no labels`);
    for (const name of match[1].split(',').map((part) => part.trim().replace(/^"|"$/g, ''))) {
      assert.ok(triage.LABELS[name], `${file} applies the label ${name}, which the script does not create`);
    }
  }
});
