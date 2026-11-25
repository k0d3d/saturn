from contextlib import redirect_stdout
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


graph = load('saturn_graph', ROOT / 'scripts' / 'saturn_graph.py')


class GraphTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='saturn-graph-')
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        (base / 'saturn').mkdir(parents=True)
        self.workspace = base / 'saturn' / 'workspace.json'
        self.workspace.write_text(json.dumps({
            'version': 2, 'tasks': [{
                'id': 't1', 'title': 'Draft launch plan', 'done': False,
                'completedAt': 0, 'due': '2026-11-26', 'createdAt': 1,
                'updatedAt': 1, 'archived': False, 'archivedAt': 0,
                'body': 'See [[Project X]] and [[note:n1]].',
                'tags': ['work'], 'source': 'local', 'externalId': None,
            }],
            'notes': {'2026-11-25': 'Met about [[Project X]].'},
            'notesV2': [{
                'id': 'n1', 'title': 'Project X', 'body': 'Ideas for launch.',
                'tags': ['work'], 'date': '2026-11-25', 'createdAt': 1,
                'updatedAt': 1, 'archived': False, 'pinned': False,
            }],
            'events': [{
                'id': 'e1', 'title': 'Launch review', 'start': 1, 'end': 2,
                'source': 'local', 'archived': False, 'createdAt': 1, 'updatedAt': 1,
            }],
            'activity': {},
            'focus': {'title': 'Open focus', 'duration': 1500, 'elapsed': 0, 'running': False},
            'sync': {'providers': {}, 'conflicts': [], 'tombstones': []},
            'insights': {},
        }))
        for name, value in [('DATA_HOME', base), ('WORKSPACE', self.workspace),
                            ('BACKUPS', base / 'omaowl-backups')]:
            patcher = patch.object(graph, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def call(self, *args):
        stream = io.StringIO()
        try:
            with redirect_stdout(stream):
                graph.main(list(args))
        except SystemExit:
            pass
        return json.loads(stream.getvalue())

    def test_link_creates_agent_edge_and_neighbors_finds_it(self):
        self.call('link', 'task:t1', 'supports', 'note:n1')
        found = self.call('neighbors', 'task:t1')['nodes']
        self.assertIn('note:n1', [row['key'] for row in found])
        row = next(row for row in found if row['key'] == 'note:n1')
        self.assertEqual(row['relation'], 'supports')
        self.assertEqual(row['origin'], 'agent')

    def test_shared_tags_create_a_tag_hub(self):
        self.call('reindex')
        found = self.call('neighbors', 'task:t1', '2')['nodes']
        self.assertIn('note:n1', [row['key'] for row in found])
        self.assertIn('tag:work', [row['key'] for row in found])

    def test_wiki_links_resolve_by_title_and_id(self):
        self.call('reindex')
        found = self.call('neighbors', 'task:t1')['nodes']
        wiki = [row for row in found if row['origin'] == 'wiki']
        self.assertEqual({row['key'] for row in wiki}, {'note:n1'})

    def test_agent_edges_survive_reindex(self):
        self.call('link', 'task:t1', 'supports', 'note:n1')
        self.call('reindex')
        found = self.call('neighbors', 'task:t1')['nodes']
        self.assertTrue(any(row['key'] == 'note:n1' and row['origin'] == 'agent' for row in found))

    def test_path_finds_shortest_route(self):
        self.call('link', 'task:t1', 'supports', 'note:n1')
        self.call('link', 'note:n1', 'leads-to', 'event:e1')
        self.assertEqual(self.call('path', 'task:t1', 'event:e1')['path'],
                         ['task:t1', 'note:n1', 'event:e1'])

    def test_missing_workspace_item_keeps_its_edges_but_is_stale(self):
        self.call('link', 'task:t1', 'supports', 'note:n1')
        state = json.loads(self.workspace.read_text())
        state['tasks'] = []
        self.workspace.write_text(json.dumps(state))
        self.call('reindex')
        found = self.call('neighbors', 'note:n1')['nodes']
        row = next(row for row in found if row['key'] == 'task:t1')
        self.assertTrue(row['stale'])

    def test_status_and_backup(self):
        self.call('reindex')
        status = self.call('status')
        self.assertEqual(status['ok'], True)
        self.assertGreater(status['nodes'], 0)
        backup = self.call('backup')
        self.assertTrue(Path(backup['path']).exists())

    def test_ambiguous_titles_are_rejected(self):
        state = json.loads(self.workspace.read_text())
        state['tasks'].append(dict(state['tasks'][0], id='t2', title='Project X'))
        self.workspace.write_text(json.dumps(state))
        result = self.call('link', 'task:t1', 'supports', 'Project X')
        self.assertFalse(result['ok'])

    def test_relations_are_constrained(self):
        result = self.call('link', 'task:t1', '../bad relation', 'note:n1')
        self.assertFalse(result['ok'])

    def at_mention(self, body):
        state = json.loads(self.workspace.read_text())
        state['tasks'][0]['body'] = body
        self.workspace.write_text(json.dumps(state))
        return self.call('reindex')

    def test_at_mention_by_unique_title_creates_edge(self):
        self.at_mention('Sync with @Project X tomorrow.')
        found = self.call('neighbors', 'task:t1')['nodes']
        mention = [row for row in found if row['origin'] == 'mention']
        self.assertEqual([row['key'] for row in mention], ['note:n1'])
        self.assertEqual(mention[0]['relation'], 'mentions')

    def test_at_mention_by_exact_id_creates_edge(self):
        self.at_mention('See @note:n1 for context.')
        found = self.call('neighbors', 'task:t1')['nodes']
        self.assertTrue(any(row['key'] == 'note:n1' and row['origin'] == 'mention'
                            for row in found))

    def test_ambiguous_at_mention_is_skipped(self):
        state = json.loads(self.workspace.read_text())
        state['tasks'].append(dict(state['tasks'][0], id='t2', title='Project X'))
        self.workspace.write_text(json.dumps(state))
        self.at_mention('Ask @Project X about this.')
        found = self.call('neighbors', 'task:t1')['nodes']
        self.assertFalse(any(row['origin'] == 'mention' for row in found))

    def test_backlinks_lists_incoming_edges(self):
        self.call('link', 'task:t1', 'supports', 'note:n1')
        found = self.call('backlinks', 'note:n1')['nodes']
        self.assertIn('task:t1', [row['key'] for row in found])
        self.assertIn('supports', [row['relation'] for row in found])


if __name__ == '__main__':
    unittest.main()
