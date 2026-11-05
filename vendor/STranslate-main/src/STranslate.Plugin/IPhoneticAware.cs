namespace STranslate.Plugin;

/// <summary>
/// 需要按用户偏好输出音标的插件实现此接口。宿主会在服务初始化与设置变化时注入。
/// </summary>
public interface IPhoneticAware
{
    /// <summary>音标体系：ipa / kk / both。</summary>
    string PhoneticSystem { get; set; }
}
