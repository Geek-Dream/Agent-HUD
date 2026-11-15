using System.Numerics;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Hosting;

namespace AgentHUD.Windows.Services;

/// <summary>
/// Shared compositor-driven motion for the HUD. Everything here runs on the
/// compositor thread so it stays smooth while the UI thread does layout work.
/// </summary>
internal static class HudMotion
{
    public const int RowEntranceMs = 420;
    public const int RowStaggerMs = 38;
    public const int MaxStaggerRows = 9;
    public const int CardEntranceMs = 360;
    public const int CardStaggerMs = 34;
    public const int PageEnterMs = 320;
    public const int PageExitMs = 180;

    /// <summary>Apple-style emphasized-decelerate: quick start, long soft settle.</summary>
    internal static CubicBezierEasingFunction Emphasized(Compositor compositor) =>
        compositor.CreateCubicBezierEasingFunction(
            new Vector2(0.16f, 1f),
            new Vector2(0.3f, 1f));

    internal static CubicBezierEasingFunction Standard(Compositor compositor) =>
        compositor.CreateCubicBezierEasingFunction(
            new Vector2(0.2f, 0f),
            new Vector2(0f, 1f));

    internal static CubicBezierEasingFunction Accelerate(Compositor compositor) =>
        compositor.CreateCubicBezierEasingFunction(
            new Vector2(0.4f, 0f),
            new Vector2(1f, 1f));

    private static LinearEasingFunction Linear(Compositor compositor) =>
        compositor.CreateLinearEasingFunction();

    /// <summary>
    /// Slides one list row up from below while fading it in. The index drives a
    /// stagger so a batch of rows streams in one after another instead of
    /// popping in together.
    /// </summary>
    public static void PlayRowEntrance(UIElement element, int index) =>
        PlayEntrance(element, index, fromY: 18f, RowEntranceMs, RowStaggerMs, MaxStaggerRows);

    /// <summary>Lighter variant used for detail cards so a page does not get noisy.</summary>
    public static void PlayCardEntrance(UIElement element, int index) =>
        PlayEntrance(element, index, fromY: 12f, CardEntranceMs, CardStaggerMs, 5);

    private static void PlayEntrance(
        UIElement element,
        int index,
        float fromY,
        int durationMs,
        int staggerMs,
        int maxStaggerRows)
    {
        ElementCompositionPreview.SetIsTranslationEnabled(element, true);
        var visual = ElementCompositionPreview.GetElementVisual(element);
        var compositor = visual.Compositor;

        var stagger = Math.Clamp(index, 0, maxStaggerRows) * staggerMs;
        var totalMs = (double)stagger + durationMs;
        var hold = (float)(stagger / totalMs);
        var ease = Emphasized(compositor);
        var linear = Linear(compositor);
        var start = new Vector3(0f, fromY, 0f);

        var opacity = compositor.CreateScalarKeyFrameAnimation();
        opacity.Duration = TimeSpan.FromMilliseconds(totalMs);
        opacity.InsertKeyFrame(0f, 0f);
        if (hold > 0f)
        {
            opacity.InsertKeyFrame(hold, 0f, linear);
        }
        opacity.InsertKeyFrame(1f, 1f, ease);

        var translation = compositor.CreateVector3KeyFrameAnimation();
        translation.Duration = TimeSpan.FromMilliseconds(totalMs);
        translation.InsertKeyFrame(0f, start);
        if (hold > 0f)
        {
            translation.InsertKeyFrame(hold, start, linear);
        }
        translation.InsertKeyFrame(1f, Vector3.Zero, ease);

        visual.StartAnimation("Opacity", opacity);
        visual.StartAnimation("Translation", translation);
    }

    /// <summary>Quick spring-like pop used when a filter chip becomes selected.</summary>
    public static void PlayScalePop(UIElement element)
    {
        var visual = ElementCompositionPreview.GetElementVisual(element);
        var compositor = visual.Compositor;
        var size = element.RenderSize;
        visual.CenterPoint = new Vector3((float)size.Width / 2f, (float)size.Height / 2f, 0f);

        var ease = Emphasized(compositor);
        var scale = compositor.CreateVector3KeyFrameAnimation();
        scale.Duration = TimeSpan.FromMilliseconds(340);
        scale.InsertKeyFrame(0f, new Vector3(0.94f, 0.94f, 1f));
        scale.InsertKeyFrame(0.55f, new Vector3(1.04f, 1.04f, 1f), ease);
        scale.InsertKeyFrame(1f, Vector3.One, ease);
        visual.StartAnimation("Scale", scale);
    }

    /// <summary>Soft fade used for chips that lose selection.</summary>
    public static void PlayFadeIn(UIElement element, int durationMs = 220)
    {
        var visual = ElementCompositionPreview.GetElementVisual(element);
        var compositor = visual.Compositor;
        var opacity = compositor.CreateScalarKeyFrameAnimation();
        opacity.Duration = TimeSpan.FromMilliseconds(durationMs);
        opacity.InsertKeyFrame(0f, 0.55f);
        opacity.InsertKeyFrame(1f, 1f, Standard(compositor));
        visual.StartAnimation("Opacity", opacity);
    }

    /// <summary>
    /// Page push-in. Start it in the same synchronous block that makes the
    /// element visible, otherwise the first frame renders unanimated.
    /// </summary>
    public static async Task PlayEnterAsync(
        UIElement element,
        float fromX,
        float fromScale = 1f,
        int durationMs = PageEnterMs)
    {
        ElementCompositionPreview.SetIsTranslationEnabled(element, true);
        var visual = ElementCompositionPreview.GetElementVisual(element);
        var compositor = visual.Compositor;
        var ease = Emphasized(compositor);
        var duration = TimeSpan.FromMilliseconds(durationMs);

        var opacity = compositor.CreateScalarKeyFrameAnimation();
        opacity.Duration = duration;
        opacity.InsertKeyFrame(0f, 0f);
        opacity.InsertKeyFrame(1f, 1f, ease);

        var translation = compositor.CreateVector3KeyFrameAnimation();
        translation.Duration = duration;
        translation.InsertKeyFrame(0f, new Vector3(fromX, 8f, 0f));
        translation.InsertKeyFrame(1f, Vector3.Zero, ease);

        visual.StartAnimation("Opacity", opacity);
        visual.StartAnimation("Translation", translation);

        if (Math.Abs(fromScale - 1f) > 0.0001f)
        {
            var size = element.RenderSize;
            visual.CenterPoint = new Vector3((float)size.Width / 2f, (float)size.Height / 2f, 0f);
            var scale = compositor.CreateVector3KeyFrameAnimation();
            scale.Duration = duration;
            scale.InsertKeyFrame(0f, new Vector3(fromScale, fromScale, 1f));
            scale.InsertKeyFrame(1f, Vector3.One, ease);
            visual.StartAnimation("Scale", scale);
        }

        await Task.Delay(durationMs);
        Reset(element);
    }

    /// <summary>Page push-out. Collapse the element only after this completes.</summary>
    public static async Task PlayExitAsync(
        UIElement element,
        float toX,
        int durationMs = PageExitMs)
    {
        ElementCompositionPreview.SetIsTranslationEnabled(element, true);
        var visual = ElementCompositionPreview.GetElementVisual(element);
        var compositor = visual.Compositor;
        var ease = Accelerate(compositor);
        var duration = TimeSpan.FromMilliseconds(durationMs);

        var opacity = compositor.CreateScalarKeyFrameAnimation();
        opacity.Duration = duration;
        opacity.InsertKeyFrame(0f, 1f);
        opacity.InsertKeyFrame(1f, 0f, ease);

        var translation = compositor.CreateVector3KeyFrameAnimation();
        translation.Duration = duration;
        translation.InsertKeyFrame(0f, Vector3.Zero);
        translation.InsertKeyFrame(1f, new Vector3(toX, 0f, 0f), ease);

        visual.StartAnimation("Opacity", opacity);
        visual.StartAnimation("Translation", translation);

        await Task.Delay(durationMs);
        Reset(element);
    }

    /// <summary>Drops every animation and restores the visual to layout defaults.</summary>
    public static void Reset(UIElement element)
    {
        var visual = ElementCompositionPreview.GetElementVisual(element);
        visual.StopAnimation("Opacity");
        visual.StopAnimation("Translation");
        visual.StopAnimation("Scale");
        visual.Opacity = 1f;
        visual.Scale = Vector3.One;
    }
}
