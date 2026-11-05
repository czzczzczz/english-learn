using STranslate.Core;
using STranslate.Helpers;
using STranslate.Plugin;
using STranslate.Services;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;

namespace STranslate.Views;

/// <summary>
/// 生词故事窗口：展示 AI 生成的短文，可朗读、复制、重新生成。
/// </summary>
public partial class StoryWindow
{
    private readonly StoryService _storyService;
    private readonly TtsService _ttsService;
    private IReadOnlyList<string> _words = [];

    public StoryWindow(StoryService storyService, TtsService ttsService)
    {
        _storyService = storyService;
        _ttsService = ttsService;
        InitializeComponent();
    }

    /// <summary>用给定生词生成故事并显示。</summary>
    public async Task LoadAsync(IReadOnlyList<string> words)
    {
        _words = words;
        await GenerateAsync();
    }

    private async Task GenerateAsync()
    {
        SetBusy(true);
        RenderStory(string.Empty);

        try
        {
            var story = await _storyService.GenerateAsync(_words);
            RenderStory(story);
        }
        catch (Exception ex)
        {
            RenderStory(ex.Message);
        }
        finally
        {
            SetBusy(false);
        }
    }

    /// <summary>把 **目标词** 渲染成加粗，其余按普通文本显示。</summary>
    private void RenderStory(string text)
    {
        var paragraph = new Paragraph { Margin = new Thickness(0) };
        var parts = (text ?? string.Empty).Split("**");

        for (var i = 0; i < parts.Length; i++)
        {
            var run = new Run(parts[i]);
            if (i % 2 == 1)
            {
                run.FontWeight = FontWeights.Bold;
                run.Foreground = (Brush)FindResource("AccentTextFillColorPrimaryBrush");
            }

            paragraph.Inlines.Add(run);
        }

        PART_Content.Document.Blocks.Clear();
        PART_Content.Document.Blocks.Add(paragraph);
    }

    /// <summary>读取当前显示的故事纯文本。</summary>
    private string GetStoryText() =>
        new TextRange(PART_Content.Document.ContentStart, PART_Content.Document.ContentEnd).Text.Trim();

    private void SetBusy(bool busy)
    {
        PART_Busy.IsActive = busy;
        PART_Busy.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        PART_Speak.IsEnabled = !busy;
    }

    private async void OnSpeakClick(object sender, RoutedEventArgs e)
    {
        var text = GetStoryText();
        if (string.IsNullOrWhiteSpace(text))
            return;

        var plugin = _ttsService.GetActiveSvc<ITtsPlugin>();
        if (plugin is null)
            return;

        try
        {
            // 只读英文部分，避免把中文对照一起念出来
            var english = text.Split("中文对照", StringSplitOptions.RemoveEmptyEntries)[0].Trim();
            await plugin.PlayAudioAsync(english);
        }
        catch
        {
            // 朗读失败不打断窗口
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
        => ClipboardHelper.SetText(GetStoryText());

    private async void OnRegenerateClick(object sender, RoutedEventArgs e) => await GenerateAsync();

    private void OnCloseClick(object sender, RoutedEventArgs e) => Close();
}
