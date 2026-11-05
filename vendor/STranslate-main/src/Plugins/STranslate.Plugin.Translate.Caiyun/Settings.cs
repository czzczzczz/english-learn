namespace STranslate.Plugin.Translate.Caiyun;

/// <summary>
/// 彩云小译插件设置。
/// </summary>
public class Settings
{
    /// <summary>
    /// 彩云开放平台 token；留空时使用内置测试 token。
    /// </summary>
    public string Token { get; set; } = DefaultToken;

    /// <summary>彩云官方文档里给出的公开测试 token，额度有限。</summary>
    public const string DefaultToken = "3975l6lr5pcbvidl6jl2";

    /// <summary>实际生效的 token。</summary>
    public string EffectiveToken => string.IsNullOrWhiteSpace(Token) ? DefaultToken : Token.Trim();
}
