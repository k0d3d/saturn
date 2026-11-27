import unittest

from scripts import tags


class TagsTest(unittest.TestCase):
    def test_pulls_meaningful_words_into_lowercase_tags(self):
        self.assertEqual(
            tags.from_title("Review Q3 Roadmap with Priya"),
            ["review", "q3", "roadmap", "priya"],
        )
        self.assertEqual(
            tags.from_title("Fix the leaky Faucet in Kitchen"),
            ["fix", "leaky", "faucet", "kitchen"],
        )

    def test_drops_function_words_date_words_and_numbers(self):
        self.assertEqual(tags.from_title("a an the and tomorrow"), [])
        self.assertEqual(tags.from_title("Pay 123 rent today"), ["pay", "rent"])
        self.assertEqual(tags.from_title("Call dentist next Mon"), ["call", "dentist"])

    def test_keeps_hashtag_words_and_unicode_letters(self):
        self.assertEqual(tags.from_title("Ship #launch notes café"), ["ship", "launch", "notes", "café"])

    def test_deduplicates_and_caps_the_tag_count(self):
        many = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
        result = tags.from_title(many)
        self.assertEqual(len(result), 8)
        self.assertEqual(len(set(result)), 8)
        self.assertEqual(tags.from_title("Milk milk MILK milk"), ["milk"])

    def test_clean_normalises_model_produced_tags(self):
        self.assertEqual(
            tags.clean(['Milk', '#Errands', 'the', 'milk', 42, '', 'x' * 50]),
            ['milk', 'errands', 'x' * 32],
        )

    def test_merging_keeps_curated_tags_and_adds_new_title_words(self):
        self.assertEqual(
            tags.merge_tags(["curated"], "Review Roadmap with Priya"),
            ["curated", "review", "roadmap", "priya"],
        )
        self.assertEqual(tags.merge_tags(["roadmap"], "Review Roadmap"), ["roadmap", "review"])


if __name__ == '__main__':
    unittest.main()
