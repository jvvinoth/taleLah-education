"""
Word-practice tutoring — the analyser must answer what the child actually
said, not a stock "Super!".

These cases encode the pedagogy: a correct attempt is named correct, a near
miss names the exact syllable to fix, a genuinely different word gets
modelled again, and no-evidence stays no-evidence.
"""
from backend.core.pronunciation import analyse_word, split_graphemes


class TestGraphemes:
    def test_tamil_syllables_stay_whole(self):
        # மீ is one syllable, not ம + ீ — a child practises syllables.
        assert split_graphemes("மீன") == ["மீ", "ன"]
        assert split_graphemes("கண்டேன்") == ["க", "ண்", "டே", "ன்"]

    def test_other_scripts_split_per_character(self):
        assert split_graphemes("鱼") == ["鱼"]
        assert split_graphemes("ikan") == ["i", "k", "a", "n"]

    def test_whitespace_dropped(self):
        assert split_graphemes(" இ லை ") == ["இ", "லை"]


class TestPerfect:
    def test_exact_word(self):
        a = analyse_word("மீன", "மீன")
        assert a.verdict == "perfect"
        assert a.focus_part == ""
        assert a.score == 1.0

    def test_word_final_pulli_is_not_a_mistake(self):
        # மீன் vs மீன is orthography, not pronunciation — must not cost a win.
        assert analyse_word("மீன்", "மீன").verdict == "perfect"

    def test_correct_word_inside_a_sentence(self):
        # Children answer with padding; the word is still there.
        assert analyse_word("இது ஒரு மீன் அம்மா", "மீன").verdict == "perfect"

    def test_target_inside_longer_word_chinese(self):
        # No word spaces in Chinese — substring must still count.
        assert analyse_word("小鱼", "鱼").verdict == "perfect"

    def test_perfect_reports_every_syllable_as_landed(self):
        # The UI lights up solid syllables — a win means all of them.
        a = analyse_word("மீனா", "மீன")  # ASR spells it long
        assert a.verdict == "perfect"
        assert "".join(a.matched_parts) == "மீன"


class TestClose:
    def test_dropped_final_syllable_names_that_syllable(self):
        a = analyse_word("மீ", "மீன")
        assert a.verdict == "close"
        assert a.focus_part == "ன"

    def test_vowel_length_slip_is_close_not_wrong(self):
        # மின for மீன — the classic slip; coach it, don't reject it.
        a = analyse_word("மின", "மீன")
        assert a.verdict == "close"
        assert a.focus_part == "மீ"

    def test_retroflex_confusion_names_the_letter(self):
        a = analyse_word("கன்டேன்", "கண்டேன்")
        assert a.verdict == "close"
        assert a.focus_part == "ண்"

    def test_dropped_vowel_sign(self):
        assert analyse_word("இல", "இலை").verdict == "close"


class TestDifferentAndUnclear:
    def test_a_different_word_is_modelled_again(self):
        a = analyse_word("நாய் ஒரு பூனை", "மீன")
        assert a.verdict == "different"

    def test_silence_is_unclear_not_wrong(self):
        a = analyse_word("", "மீன")
        assert a.verdict == "unclear"
        assert a.heard is False

    def test_asr_noise_on_a_quiet_mic_is_unclear(self):
        # Sarvam transcribes near-silence as a single stray cluster ("ம்").
        # Correcting a child for that would be feedback on no evidence.
        a = analyse_word("ம்", "மீன")
        assert a.verdict == "unclear"
        assert a.heard is False

    def test_a_real_short_attempt_is_still_judged(self):
        # One cluster that genuinely matches must NOT be dismissed as noise.
        assert analyse_word("மீ", "மீன").verdict == "close"


class TestPrivacy:
    def test_nothing_returned_comes_from_the_transcript(self):
        # AC-07 — every exposed string must be built from the target word.
        target = "மீன"
        a = analyse_word("நாய் பூனை யானை", target)
        assert a.focus_part in split_graphemes(target)
        for part in a.matched_parts:
            assert part in split_graphemes(target)
