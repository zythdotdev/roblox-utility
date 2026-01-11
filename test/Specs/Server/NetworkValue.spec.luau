return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Connection = require(ReplicatedStorage.Modules.Connection)
	local NetworkValue = Connection.NetworkValue

	NetworkValue.new("TestValue1", ReplicatedStorage, 123)
	NetworkValue.new("TestValue2", ReplicatedStorage, 123)
	NetworkValue.new("TestValue5", ReplicatedStorage, 123)

    describe("NetworkValueServer", function()
		it("Should override local value when server updates it", function()
			local value = NetworkValue.new("TestValue3", ReplicatedStorage, 123)
			task.delay(1, function()
				value:Set(500)
			end)
		end)
		it("Should fire connection when value is changed server-side", function()
			local value = NetworkValue.new("TestValue4", ReplicatedStorage, 123)
			task.delay(1, function()
				value:Set(789)
			end)
		end)
	end)
end