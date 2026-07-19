import Foundation
import JAgent
import JProactive

/// Lets the agent schedule recurring work for itself.
enum ProactiveTools {
    static func registry(cronStore: CronStore) -> [ToolSpec] {
        [scheduleTask(cronStore), listTasks(cronStore)]
    }

    private static func scheduleTask(_ cronStore: CronStore) -> ToolSpec {
        ToolSpec(
            name: "schedule_task",
            description: "Schedule a recurring task. 'cron' is a 5-field expression (minute hour day-of-month month day-of-week), e.g. '0 9 * * *' = 9am daily, '*/30 * * * *' = every 30 min. 'prompt' is what to do when it fires.",
            parameters: obj([("name", "Short task name"), ("cron", "5-field cron expression"), ("prompt", "What to do when it runs")], required: ["name", "cron", "prompt"]),
            tier: .externalEffect,
            summarize: { "Schedule “\(str($0, "name") ?? "")” (\(str($0, "cron") ?? ""))" }
        ) { input, _ in
            guard let name = str(input, "name"), let cron = str(input, "cron"), let prompt = str(input, "prompt") else {
                return ToolOutput("Missing 'name', 'cron', or 'prompt'.", isError: true)
            }
            guard let job = await cronStore.create(name: name, cronExpr: cron, prompt: prompt) else {
                return ToolOutput("Invalid cron expression: \(cron)", isError: true)
            }
            return ToolOutput("Scheduled “\(name)” — next run \(job.nextRunAt.formatted(date: .abbreviated, time: .shortened)).")
        }
    }

    private static func listTasks(_ cronStore: CronStore) -> ToolSpec {
        ToolSpec(
            name: "list_scheduled_tasks",
            description: "List the recurring tasks you've scheduled.",
            parameters: obj([], required: []),
            tier: .readOnly
        ) { _, _ in
            let jobs = await cronStore.list()
            if jobs.isEmpty { return ToolOutput("No scheduled tasks.") }
            return ToolOutput(jobs.map { "\($0.enabled ? "•" : "○") \($0.name) (\($0.cronExpr)) — next \($0.nextRunAt.formatted(date: .abbreviated, time: .shortened))" }.joined(separator: "\n"))
        }
    }
}
