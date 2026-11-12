using System.Text.Json;
using AgentHUD.Core;
using Xunit;

namespace AgentHUD.Core.Tests;

public sealed class OpenCodeTests
{
    private static readonly DateTimeOffset Base =
        DateTimeOffset.FromUnixTimeMilliseconds(1_800_000_000_000);

    [Fact]
    public void QuestionMapsToWaitingAndPreservesPromptAndFiles()
    {
        var session = Parse(Record(includeQuestion: true, includeSummary: true));

        Assert.Equal(AgentProvider.OpenCode, session.Provider);
        Assert.Equal(AgentStatus.WaitingUser, session.Status);
        Assert.Equal("增加 OpenCode 支持", session.Title);
        Assert.Equal("/tmp/Agent-HUD/Models.swift", Assert.Single(session.CurrentFiles));
        Assert.Equal("增加 OpenCode 支持", session.LatestUserPrompt?.Text);
    }

    [Fact]
    public void FinalTextMapsToCompletedRun()
    {
        var session = Parse(Record(includeQuestion: false, includeSummary: true));

        Assert.Equal(AgentStatus.Completed, session.Status);
        Assert.Single(session.Runs);
        Assert.Equal("OpenCode 已接入。", session.Runs[0].Summary);
    }

    [Fact]
    public void ToolErrorMapsToFailed()
    {
        var session = Parse(Record(includeQuestion: false, includeSummary: false, includeError: true));

        Assert.Equal(AgentStatus.Failed, session.Status);
    }

    private static AgentSession Parse(OpenCodeSessionRecord record) =>
        OpenCodeAdapter.Parse(
            record,
            "/tmp/opencode.db",
            providerIsRunning: true,
            Base.AddSeconds(100));

    private static OpenCodeSessionRecord Record(
        bool includeQuestion,
        bool includeSummary,
        bool includeError = false)
    {
        var messages = new[]
        {
            Event("msg-user", 0, "{\"role\":\"user\"}"),
            Event("msg-assistant", 1, "{\"role\":\"assistant\",\"time\":{\"completed\":1800000004000}}")
        };
        var parts = new List<OpenCodeEvent>
        {
            Event(
                "part-user-text",
                0,
                "{\"type\":\"text\",\"text\":\"增加 OpenCode 支持\"}",
                "msg-user")
        };
        if (includeQuestion)
        {
            parts.Add(Event(
                "part-question",
                2,
                "{\"type\":\"tool\",\"tool\":\"question\",\"state\":{\"status\":\"running\",\"input\":{\"filePath\":\"/tmp/Agent-HUD/Models.swift\"}}}",
                "msg-assistant"));
        }
        if (includeSummary)
        {
            parts.Add(Event(
                "part-summary",
                4,
                "{\"type\":\"text\",\"text\":\"OpenCode 已接入。\"}",
                "msg-assistant"));
        }
        if (includeError)
        {
            parts.Add(Event(
                "part-error",
                3,
                "{\"type\":\"tool\",\"tool\":\"bash\",\"state\":{\"status\":\"error\"}}",
                "msg-assistant"));
        }
        return new OpenCodeSessionRecord(
            "ses_test",
            "/tmp/Agent-HUD",
            "OpenCode 会话",
            Base,
            Base.AddSeconds(4),
            messages.Reverse().ToArray(),
            parts.AsEnumerable().Reverse().ToArray());
    }

    private static OpenCodeEvent Event(
        string id,
        int seconds,
        string json,
        string? messageID = null)
    {
        using var document = JsonDocument.Parse(json);
        return new OpenCodeEvent(
            id,
            Base.AddSeconds(seconds),
            document.RootElement.Clone(),
            messageID);
    }
}
