--!nocheck

local NotificationSubscriptionManager = require(script.Parent:WaitForChild("NotificationSubscriptionManager"))

NotificationSubscriptionManager.Start()
NotificationSubscriptionManager.SubscribeDefaults()

return NotificationSubscriptionManager
