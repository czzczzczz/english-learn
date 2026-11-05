import io

p = r"D:/vibe_coding/english_learn/vendor/STranslate-main/src/STranslate/ViewModels/MainWindowViewModel.cs"
s = io.open(p, encoding='utf-8-sig').read()


def replace_once(text, old, new, label):
    assert old in text, "MISSING: " + label
    assert text.count(old) == 1, "AMBIGUOUS: " + label + " count=" + str(text.count(old))
    print("ok:", label)
    return text.replace(old, new, 1)


s = replace_once(
    s,
    "        OcrService ocrService,\n        Settings settings,",
    "        OcrService ocrService,\n        DictionaryService dictionaryService,\n        Settings settings,",
    "ctor-params")

s = replace_once(
    s,
    "        _ocrService = ocrService;",
    "        _ocrService = ocrService;\n        _dictionaryService = dictionaryService;",
    "ctor-body")

s = replace_once(
    s,
    "    private readonly OcrService _ocrService;",
    "    private readonly OcrService _ocrService;\n    private readonly DictionaryService _dictionaryService;",
    "field")

s = replace_once(
    s,
    '        var added = VocabularyStore.Add(text, meaning: TakeCurrentMeaning());\n'
    '        _snackbar.ShowSuccess(_i18n.GetTranslation(added ? "OperationSuccess" : "VocabularyAlreadyExists"));\n'
    "        return Task.CompletedTask;",
    '        var added = VocabularyStore.Add(text, meaning: TakeCurrentMeaning());\n'
    '        _snackbar.ShowSuccess(_i18n.GetTranslation(added ? "OperationSuccess" : "VocabularyAlreadyExists"));\n'
    "        EnrichVocabularyInBackground(text);\n"
    "        return Task.CompletedTask;",
    "save-command")

s = replace_once(
    s,
    '        var added = VocabularyStore.Add(word, note: note, source: service.DisplayName);\n'
    '        _snackbar.ShowSuccess(_i18n.GetTranslation(added ? "OperationSuccess" : "VocabularyAlreadyExists"));',
    '        var added = VocabularyStore.Add(word, note: note, source: service.DisplayName);\n'
    '        _snackbar.ShowSuccess(_i18n.GetTranslation(added ? "OperationSuccess" : "VocabularyAlreadyExists"));\n'
    "        EnrichVocabularyInBackground(word);",
    "save-with-note")

helper = (
    "    /// <summary>后台查词典补全音标与英文释义，失败静默跳过。</summary>\n"
    "    private void EnrichVocabularyInBackground(string word)\n"
    "    {\n"
    "        var key = (word ?? string.Empty).Trim().ToLowerInvariant();\n"
    "        if (key.Length == 0)\n"
    "            return;\n"
    "\n"
    "        _ = Task.Run(async () =>\n"
    "        {\n"
    "            try\n"
    "            {\n"
    "                var info = await _dictionaryService.LookupAsync(key).ConfigureAwait(false);\n"
    "                if (info is null)\n"
    "                    return;\n"
    "\n"
    "                VocabularyStore.Enrich(key, info.Phonetic, info.Meaning);\n"
    "            }\n"
    "            catch (Exception ex)\n"
    "            {\n"
    '                _logger.LogDebug(ex, "补充生词信息失败：{Word}", key);\n'
    "            }\n"
    "        });\n"
    "    }\n"
    "\n"
    "    /// <summary>取当前翻译结果首行，作为生词本的简短释义。</summary>"
)

s = replace_once(s, "    /// <summary>取当前翻译结果首行，作为生词本的简短释义。</summary>", helper, "helper")

io.open(p, "w", encoding="utf-8-sig", newline="").write(s)
print("MainWindowViewModel written")
