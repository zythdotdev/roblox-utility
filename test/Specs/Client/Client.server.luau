local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage.TestEZ)

TestEZ.TestBootstrap:run({
	ReplicatedStorage.Tests.Client["Bag.spec"],
	ReplicatedStorage.Tests.Client["Event.spec"],
	ReplicatedStorage.Tests.Client["Value.spec"],
	ReplicatedStorage.Tests.Client["Zone.spec"],
	ReplicatedStorage.Tests.Client["NetworkEvent.spec"],
	ReplicatedStorage.Tests.Client["NetworkRequest.spec"],
	ReplicatedStorage.Tests.Client["NetworkValue.spec"],
})