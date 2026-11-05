import io

p = r"D:/vibe_coding/english_learn/vendor/STranslate-main/src/STranslate/Services/VocabularyStore.cs"
s = io.open(p, encoding='utf-8-sig').read()

anchor = "    /// <summary>删除一个词条。</summary>"
assert anchor in s, "anchor missing"
assert "public bool Enrich" not in s, "already present"

body = (
    "    /// <summary>\n"
    "    /// 用词典结果补全词条：音标填空位，笔记为空时填英文释义。\n"
    "    /// </summary>\n"
    "    /// <param name=\"key\">词条键（小写）。</param>\n"
    "    /// <param name=\"phonetic\">音标。</param>\n"
    "    /// <param name=\"meaning\">英文释义。</param>\n"
    "    /// <returns>是否有字段被更新。</returns>\n"
    "    public bool Enrich(string key, string phonetic, string meaning)\n"
    "    {\n"
    "        if (string.IsNullOrWhiteSpace(key))\n"
    "            return false;\n"
    "\n"
    "        lock (_gate)\n"
    "        {\n"
    "            var entry = Entries.FirstOrDefault(e => string.Equals(e.Key, key, StringComparison.Ordinal));\n"
    "            if (entry is null)\n"
    "                return false;\n"
    "\n"
    "            var changed = false;\n"
    "            if (!string.IsNullOrWhiteSpace(phonetic) && string.IsNullOrWhiteSpace(entry.Phonetic))\n"
    "            {\n"
    "                entry.Phonetic = phonetic;\n"
    "                changed = true;\n"
    "            }\n"
    "\n"
    "            if (!string.IsNullOrWhiteSpace(meaning) && string.IsNullOrWhiteSpace(entry.Note))\n"
    "            {\n"
    "                entry.Note = meaning;\n"
    "                changed = true;\n"
    "            }\n"
    "\n"
    "            if (!changed)\n"
    "                return false;\n"
    "\n"
    "            OnChanged();\n"
    "            Save();\n"
    "            return true;\n"
    "        }\n"
    "    }\n"
    "\n"
)

s = s.replace(anchor, body + anchor, 1)
io.open(p, "w", encoding="utf-8-sig", newline="").write(s)
print("VocabularyStore.Enrich added")
