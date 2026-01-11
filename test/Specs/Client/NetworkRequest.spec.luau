return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Connection = require(ReplicatedStorage.Modules.Connection)
	local NetworkRequest = Connection.NetworkRequest

    describe("NetworkRequestClient", function()
		it("Should create a new network request", function()
			local request = NetworkRequest.new("TestRequest1", ReplicatedStorage)
			expect(request).to.be.ok()
			expect(request.className).to.equal("NetworkRequest")
		end)
		it("Should be destroyable", function()
			local request = NetworkRequest.new("TestRequest2", ReplicatedStorage)
			request:Destroy()
			expect(request._RemoteFunction).to.equal(nil)
		end)
		it("Should pass arguments and receive a response", function()
			local request = NetworkRequest.new("TestRequest3", ReplicatedStorage)
			local response = request:InvokeAsync(1, "test", true)
			expect(response).to.equal(1, "test", true)
		end)
		it("Should handle multiple requests", function()
			local request = NetworkRequest.new("TestRequest4", ReplicatedStorage)
			local responses = {}
			for i = 1, 5 do
				table.insert(responses, {request:InvokeAsync(i)})
			end
			for i, response in ipairs(responses) do
				expect(response[1]).to.equal(i)
			end
		end)
	end)
end