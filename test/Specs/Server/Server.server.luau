local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage.TestEZ)

TestEZ.TestBootstrap:run({
	ReplicatedStorage.Tests.Server["NetworkEvent.spec"],
	ReplicatedStorage.Tests.Server["NetworkRequest.spec"],
	ReplicatedStorage.Tests.Server["NetworkValue.spec"],
})