using STranslate.Plugin;
using System.ComponentModel;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace STranslate.Core;

// 历史模型保留为纯内存数据结构，数据库层已删除

public class HistoryModel
{
    /// <summary>
    ///     记录标识（纯内存自增，仅用于比较）
    /// </summary>
    public long Id { get; set; }

    /// <summary>
    ///     记录时间
    /// </summary>
    public DateTime Time { get; set; }

    /// <summary>
    ///     源语言
    /// </summary>
    public string SourceLang { get; set; } = string.Empty;

    /// <summary>
    ///     目标语言
    /// </summary>
    public string TargetLang { get; set; } = string.Empty;

    /// <summary>
    ///     实际参与翻译的源语言（识别后）
    /// </summary>
    public string? EffectiveSourceLang { get; set; }

    /// <summary>
    ///     实际参与翻译的目标语言（识别后）
    /// </summary>
    public string? EffectiveTargetLang { get; set; }

    /// <summary>
    ///     需翻译内容
    /// </summary>
    public string SourceText { get; set; } = string.Empty;

    /// <summary>
    ///     收藏
    /// </summary>
    public bool Favorite { get; set; }

    /// <summary>
    ///     备注
    /// </summary>
    public string Remark { get; set; } = "";

    /// <summary>
    ///     数据的 JSON 字符串表示(存储到数据库)
    /// </summary>
    public string RawData
    {
        get => JsonSerializer.Serialize(Data, JsonOption);
        set => Data = string.IsNullOrEmpty(value) ? [] : JsonSerializer.Deserialize<List<HistoryData>>(value, JsonOption) ?? [];
    }

    /// <summary>
    ///     数据列表(业务使用,不映射到数据库)
    /// </summary>
    public List<HistoryData> Data { get; set; } = [];

    public override bool Equals(object? obj)
    {
        if (obj is HistoryModel other)
            return Id == other.Id;  // 仅比较主键
        return false;
    }

    public override int GetHashCode() => Id.GetHashCode();

    internal bool HasData(Service svc)
    {
        if (svc.Plugin is ITranslatePlugin tPlugin)
            return Data.Any(d =>
                d.PluginID == svc.MetaData.PluginID &&
                d.ServiceID == svc.ServiceID &&
                d.TransResult != null &&
                d.TransResult.IsSuccess &&
                !string.IsNullOrWhiteSpace(d.TransResult.Text) &&
                (!(svc.Options?.AutoBackTranslation ?? false) || (d.TransBackResult != null && d.TransBackResult.IsSuccess && !string.IsNullOrWhiteSpace(d.TransBackResult.Text)))
            );
        else
            return Data.Any(d =>
                d.PluginID == svc.MetaData.PluginID &&
                d.ServiceID == svc.ServiceID &&
                d.DictResult != null &&
                d.DictResult.ResultType != DictionaryResultType.None &&
                d.DictResult.ResultType != DictionaryResultType.Error
            );
    }

    internal HistoryData? GetData(Service svc) =>
        Data.FirstOrDefault(d => d.PluginID == svc.MetaData.PluginID && d.ServiceID == svc.ServiceID);

    internal static JsonSerializerOptions JsonOption =>
        new()
        {
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
            Converters =
            {
                new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)
            }
        };
}

public class HistoryData
{
    public string PluginID { get; set; } = string.Empty;
    public string ServiceID { get; set; } = string.Empty;
    public string? ServiceDisplayName { get; set; }
    public TranslateResult? TransResult { get; set; }
    public TranslateResult? TransBackResult { get; set; }
    public DictionaryResult? DictResult { get; set; }

    public HistoryData()
    {
    }

    public HistoryData(Service svc)
    {
        PluginID = svc.MetaData.PluginID;
        ServiceID = svc.ServiceID;
        ServiceDisplayName = svc.DisplayName;
    }
}

