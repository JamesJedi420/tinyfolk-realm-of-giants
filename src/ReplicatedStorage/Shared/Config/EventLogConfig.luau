--!strict

local EventLogConfig: any = {}

EventLogConfig.MaxRecentEvents = 200

EventLogConfig.Severity = {
	Info = "info",
	Warn = "warn",
	Error = "error",
}

EventLogConfig.DefaultSeverity = EventLogConfig.Severity.Info

return EventLogConfig
