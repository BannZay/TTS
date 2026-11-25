dofile("../TTS/Banned.lua")
local function eq(a, b, msg) assert(a == b, msg .. ": got '" .. tostring(a) .. "'") end
local B = { badword = "mask", ["very bad"] = "skip" }
eq((TTS_FilterBanned("hello world", B)), "hello world", "clean text untouched")
eq((TTS_FilterBanned("hello Badword!", B)), "hello ba!", "mask keeps the first syllable")
eq((TTS_FilterBanned("badword badword badword", B)), "ba ba ba", "chant")
eq((TTS_FilterBanned("say very bad things", B)), "say things", "skip removes the phrase")
assert(not TTS_FilterBanned("very, BAD!", B):find("%w"), "skip through punctuation, no word left")
eq((TTS_FilterBanned("b4dw0rd", B)), "ba", "look-alike characters")
eq((TTS_FilterBanned("b.a.d.w.o.r.d", B)), "ba", "dotted letters")
eq((TTS_FilterBanned("b a d w o r d now", B)), "ba now", "spaced letters")
eq((TTS_FilterBanned("badwords", B)), "ba", "plural is one letter off")
eq((TTS_FilterBanned("badwordsss", B)), "badwordsss", "two letters off is another word")
eq((TTS_FilterBanned("bad word", B)), "bad word", "two words are not one phrase word")
-- by sound: other spellings, doubled letters, k for c
local N = { carrot = "mask", bigot = "skip" }
eq((TTS_FilterBanned("karot", N)), "ka", "k for c, one r")
eq((TTS_FilterBanned("kerrott", N)), "ke", "other vowel and doubled letters")
eq((TTS_FilterBanned("carrut", N)), "ca", "vowel changed")
eq((TTS_FilterBanned("garden", N)), "garden", "different sound")
eq((TTS_FilterBanned("bigot", { bigot = "skip", bigat = "allow" })), "", "exact word still caught")
-- short words are matched exactly only
eq((TTS_FilterBanned("bat bit", { bot = "skip" })), "bat bit", "short key: no sound match")
eq((TTS_FilterBanned("bot", { bot = "skip" })), "", "short key: exact match")
-- allow list: an innocent word that sounds like a banned one
local A = { carrot = "mask", carat = "allow" }
eq((TTS_FilterBanned("a carat ring", A)), "a carat ring", "allowed word is not matched by sound")
eq((TTS_FilterBanned("a karot ring", A)), "a ka ring", "other spellings still caught")
eq((TTS_FilterBanned("very good", B)), "very good", "half a phrase is not a match")
eq((TTS_FilterBanned("a b c", { abc = "skip" })), "", "three single letters are joined")
eq((TTS_FilterBanned("I am at it", { amat = "skip" })), "I am at it", "short words stay apart")
local both = { badword = "mask", ["badword now"] = "skip" }
eq((TTS_FilterBanned("badword now", both)), "", "skip wins over mask")
local _, changed = TTS_FilterBanned("fine", B); eq(changed, false, "unchanged flag")
eq((TTS_FilterBanned("anything", {})), "anything", "empty list")
local m = {}
assert(not TTS_AddBanned(m, "bad!", "mask"), "symbols refused")
assert(not TTS_AddBanned(m, "  ", "mask"), "empty refused")
assert(not TTS_AddBanned(m, "word", "other"), "unknown mode refused")
assert(TTS_AddBanned(m, "  Two   WORDS ", "skip"))
eq(m["two words"], "skip", "key lowercased and spaces collapsed")
eq((TTS_FilterBanned("karot", N, true)), "karot", "exact only: no sound match")
eq((TTS_FilterBanned("carrot", N, true)), "ca", "exact only: spelling still matched")
print("banned tests passed")

