return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Connection = require(ReplicatedStorage.Modules.Connection)
	local NetworkRequest = Connection.NetworkRequest

	NetworkRequest.new("TestRequest1", ReplicatedStorage)
	NetworkRequest.new("TestRequest2", ReplicatedStorage)

    describe("NetworkRequestServer", function()
		it("Should pass arguments and receive a response", function()
			local request = NetworkRequest.new("TestRequest3", ReplicatedStorage)
			request:SetCallback(function(player, number, string, boolean)
				return number, string, boolean
			end)
		end)
		it("Should handle multiple requests", function()
			local request = NetworkRequest.new("TestRequest4", ReplicatedStorage)
			request:SetCallback(function(player, i)
				return i
			end)
		end)
	end)
end