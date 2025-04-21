local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage.TestEZ)

TestEZ.TestBootstrap:run({
	ReplicatedStorage.Modules.Bag["Bag.spec"],
	ReplicatedStorage.Modules.Event["Event.spec"],
	ReplicatedStorage.Modules.Value["Value.spec"],
	ReplicatedStorage.Modules.Zone["Zone.spec"],
})