'use strict';

// Triage of new and edited issues, called by .github/workflows/issue-triage.yml.
// It labels an issue from what its form holds, asks for what is missing, and
// removes its own labels once the issue is fixed. The text of an issue is only
// read as data here, and is never put in a command. The tests are in
// triage.test.js, which also check this file against the issue templates.

const MARKERS = {
  repro: '<!-- triage:needs-repro -->',
  secret: '<!-- triage:needs-redaction -->',
};

// The answers of the Component dropdown, and the label that each one gets. The
// bug report and the feature request must offer exactly these answers, plus
// "Not sure".
const COMPONENTS = {
  'Binder and the scrive tree': 'binder',
  'Panes and windows': 'panes',
  'Corkboard, Outliner, and lists': 'views',
  'Writing tools (Scrivenings, Focus, Spotlight, Quill)': 'writing-tools',
  'Goals and progress': 'progress',
  'Data on disk (project, session, snapshots, recovery)': 'data',
  'Compile and language tools (Pandoc, tagger, dictionary)': 'compile',
  'Popups, commands, palette, and menu': 'ui',
};

// The answers of the "Where do you run Vim?" dropdown that mean a GUI.
const GUI_ENVIRONMENTS = ['gVim', 'MacVim', 'Other GUI Vim'];

// Every label that the templates or this script use. A label that a template
// names but the repository lacks is silently not applied, so run the workflow
// by hand once to create them all.
const LABELS = {
  'bug': {color: 'd73a4a', description: "Something isn't working"},
  'documentation': {color: '0075ca', description: 'Improvements or additions to documentation'},
  'enhancement': {color: 'a2eeef', description: 'New feature or request'},
  'good first issue': {color: '7057ff', description: 'Good for newcomers'},
  'translation': {color: 'fbca04', description: 'A language, or the text of one'},
  'needs-triage': {color: 'ededed', description: 'Not yet reviewed by a maintainer'},
  'needs-repro': {color: 'd93f0b', description: 'Needs a minimal vimrc that reproduces the problem'},
  'needs-redaction': {color: 'b60205', description: 'Holds a secret or private text that must be removed'},
  'gui': {color: '0e8a16', description: 'Happens in gVim or MacVim'},
  'binder': {color: '1d76db', description: 'Binder and the scrive tree'},
  'panes': {color: '1d76db', description: 'Panes and windows'},
  'views': {color: '1d76db', description: 'Corkboard, Outliner, and lists'},
  'writing-tools': {color: '1d76db', description: 'Scrivenings, Focus, Spotlight, and Quill'},
  'progress': {color: '1d76db', description: 'Goals and progress'},
  'data': {color: '1d76db', description: 'Project, session, snapshots, and recovery'},
  'compile': {color: '1d76db', description: 'Compile, tagger, and dictionary'},
  'ui': {color: '1d76db', description: 'Popups, commands, palette, and menu'},
};

// A value that is plainly not a key, as in api_key = "YOUR_KEY_HERE".
const PLACEHOLDER = /^(x{4,}|\*{4,}|<[^>]*>|.*(your|example|placeholder|redacted|here).*)$/i;

// FUNCTION: Return the answer of a form field, which GitHub writes under the
// heading "### label", or an empty string when it is missing or unanswered.
function section(body, heading) {
  const escaped = heading.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = (body || '').match(new RegExp(`### ${escaped}\\s*\\n\\n([\\s\\S]*?)(?=\\n\\n###|$)`));
  const text = match ? match[1].trim() : '';
  return text === '_No response_' ? '' : text;
}

// FUNCTION: Return the lines of a vimrc that do something: no blank lines, no
// comments, and no code fence, which GitHub adds around a field with render.
function vimrcLines(text) {
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line !== '' && !line.startsWith('```') && !line.startsWith('"') && !line.startsWith('#'));
}

// FUNCTION: Return why a vimrc cannot reproduce a Bartleby bug, or an empty
// string when it can. It must load Bartleby and Logger, which Bartleby needs.
function vimrcProblem(text) {
  const lines = vimrcLines(text);
  if (lines.length === 0) {
    return 'it is empty';
  }
  const joined = lines.join('\n').toLowerCase();
  if (!joined.includes('bartleby')) {
    return 'it does not load Bartleby';
  }
  if (!joined.includes('logger')) {
    return 'it does not load Logger, which Bartleby needs';
  }
  return '';
}

// FUNCTION: Return true when the text assigns a value to something named
// api_key, as a vimrc with a dictionary or thesaurus key does.
function leaksKey(body) {
  const pattern = /api_key['"\]]*\s*[=:]\s*["']([^"'\s]{8,})["']/gi;
  let match;
  while ((match = pattern.exec(body || '')) !== null) {
    if (!PLACEHOLDER.test(match[1])) {
      return true;
    }
  }
  return false;
}

function reproComment(problem) {
  return `${MARKERS.repro}
Thanks for reporting! The minimal vimrc in this report does not help us reproduce the problem yet, because ${problem}.

Please edit the issue and replace it with a vimrc that loads only Bartleby and Logger, for example:

\`\`\`vim
set nocompatible
set rtp+=/path/to/bartleby,/path/to/Logger
filetype plugin on
syntax on
\`\`\`

Start Vim with \`vim -u that-file\`, and check that the problem still happens. The \`needs-repro\` label goes away when the vimrc is fixed.`;
}

function secretComment() {
  return `${MARKERS.secret}
This issue seems to hold an API key. Please edit the issue to remove it, and rotate the key with its provider, because the edit history of an issue stays visible. Please remove private text from your manuscript as well.`;
}

// FUNCTION: Decide what to do for an issue, from its labels and its text. Return
// the labels to add, the labels to remove, and the comments to make once. It
// removes only needs-repro and needs-redaction, so that a label that a
// maintainer added stays.
function analyze(issue) {
  const body = issue.body || '';
  const have = new Set((issue.labels || []).map((label) => label.name));
  const add = new Set();
  const remove = new Set();
  const comments = [];

  if (have.has('bug')) {
    const problem = vimrcProblem(section(body, 'Minimal vimrc'));
    if (problem !== '') {
      add.add('needs-repro');
      comments.push({marker: MARKERS.repro, text: reproComment(problem)});
    } else {
      remove.add('needs-repro');
    }
  }

  if (leaksKey(body)) {
    add.add('needs-redaction');
    comments.push({marker: MARKERS.secret, text: secretComment()});
  } else {
    remove.add('needs-redaction');
  }

  const component = COMPONENTS[section(body, 'Component')];
  if (component) {
    add.add(component);
  }

  if (GUI_ENVIRONMENTS.includes(section(body, 'Where do you run Vim?'))) {
    add.add('gui');
  }

  if (have.has('documentation') && section(body, 'Type of documentation issue') === 'Typo or grammatical error') {
    add.add('good first issue');
  }

  return {
    add: [...add].filter((name) => !have.has(name)),
    remove: [...remove].filter((name) => have.has(name)),
    comments,
  };
}

// FUNCTION: Run fn, and report a failure as a warning, so that one failed call
// does not stop the others.
async function attempt(core, what, fn) {
  try {
    return await fn();
  } catch (error) {
    core.warning(`${what} failed: ${error.message}`);
    return undefined;
  }
}

// FUNCTION: Create a label, unless it exists, which GitHub answers with 422.
async function ensureLabel(github, owner, repo, name) {
  const info = LABELS[name] || {color: 'ededed', description: ''};
  try {
    await github.rest.issues.createLabel({owner, repo, name, color: info.color, description: info.description});
  } catch (error) {
    if (error.status !== 422) {
      throw error;
    }
  }
}

async function triageIssue({github, context, core}) {
  const issue = context.payload.issue;
  const {owner, repo} = context.repo;
  const plan = analyze(issue);

  for (const name of plan.add) {
    await attempt(core, `creating the label ${name}`, () => ensureLabel(github, owner, repo, name));
  }

  if (plan.comments.length > 0) {
    const existing = (await attempt(core, 'listing the comments', () =>
      github.paginate(github.rest.issues.listComments, {owner, repo, issue_number: issue.number}))) || [];
    for (const comment of plan.comments) {
      if (existing.some((old) => (old.body || '').includes(comment.marker))) {
        continue;
      }
      await attempt(core, 'posting a comment', () =>
        github.rest.issues.createComment({owner, repo, issue_number: issue.number, body: comment.text}));
    }
  }

  if (plan.add.length > 0) {
    await attempt(core, 'adding labels', () =>
      github.rest.issues.addLabels({owner, repo, issue_number: issue.number, labels: plan.add}));
  }

  for (const name of plan.remove) {
    await attempt(core, `removing the label ${name}`, () =>
      github.rest.issues.removeLabel({owner, repo, issue_number: issue.number, name}));
  }
}

// FUNCTION: Create every label that the templates and this script use.
async function syncLabels({github, context, core}) {
  const {owner, repo} = context.repo;
  for (const name of Object.keys(LABELS)) {
    await attempt(core, `creating the label ${name}`, () => ensureLabel(github, owner, repo, name));
  }
}

async function run({github, context, core}) {
  if (context.eventName === 'workflow_dispatch') {
    await syncLabels({github, context, core});
  } else {
    await triageIssue({github, context, core});
  }
}

module.exports = {run, analyze, section, vimrcProblem, leaksKey, COMPONENTS, GUI_ENVIRONMENTS, LABELS, MARKERS};
