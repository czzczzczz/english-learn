import io

p = r"D:/vibe_coding/english_learn/vendor/STranslate-main/src/STranslate/ViewModels/MainWindowViewModel.cs"
s = io.open(p, encoding='utf-8-sig').read()

NL = chr(10)
BS = chr(92)  # backslash

bad = (
    '            .Replace("' + NL + '", "' + NL + '")' + NL +
    "            .Split('" + NL + "')" + NL +
    '            .Select(line => line.Trim())' + NL +
    '            .Where(line => line.Length > 0);' + NL +
    NL +
    "        return string.Join('" + NL + "', lines);"
)

good = (
    '            .Replace("' + BS + 'r' + BS + 'n", "' + BS + 'n")' + NL +
    "            .Split('" + BS + "n')" + NL +
    '            .Select(line => line.Trim())' + NL +
    '            .Where(line => line.Length > 0);' + NL +
    NL +
    "        return string.Join('" + BS + "n', lines);"
)

assert bad in s, "anchor not found"
s = s.replace(bad, good, 1)
io.open(p, 'w', encoding='utf-8-sig', newline='').write(s)
print("NormalizeOcrText escapes fixed")
