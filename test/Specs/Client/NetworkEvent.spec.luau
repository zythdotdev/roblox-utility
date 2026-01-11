return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Connection = require(ReplicatedStorage.Modules.Connection)
	local NetworkEvent = Connection.NetworkEvent

    describe("NetworkEventClient", function()
		it("Should create a new network event", function()
			local event = NetworkEvent.new("TestEvent1", ReplicatedStorage)
			expect(event).to.be.ok()
			expect(event.className).to.equal("NetworkEvent")
		end)
		it("Should connect and fire the event", function()
			local event = NetworkEvent.new("TestEvent2", ReplicatedStorage)
			local fired = false
			local connection = event:Connect(function(...)
				fired = true
			end)
			task.delay(1, function()
				expect(fired).to.equal(true)
				connection:Disconnect()
			end)
		end)
		it("Should pass arguments when fired", function()
			local event = NetworkEvent.new("TestEvent3", ReplicatedStorage)
			local receivedArgs = {}
			local connection = event:Connect(function(...)
				receivedArgs = {...}
			end)
			task.delay(1, function()
				expect(receivedArgs[1]).to.equal(1)
				expect(receivedArgs[2]).to.equal("test")
				expect(receivedArgs[3]).to.equal(true)
				connection:Disconnect()
			end)
		end)
		it("Should disconnect properly", function()
			local event = NetworkEvent.new("TestEvent4", ReplicatedStorage)
			local fired = false
			local connection = event:Connect(function(...)
				fired = true
			end)
			connection:Disconnect()
			task.delay(1, function()
				expect(fired).to.equal(false)
			end)
		end)
		it("Should allow multiple connections", function()
			local event = NetworkEvent.new("TestEvent5", ReplicatedStorage)
			local fireCount = 0
			local connection1 = event:Connect(function()
				fireCount += 1
			end)
			local connection2 = event:Connect(function()
				fireCount += 1
			end)
			task.delay(1, function()
				expect(fireCount).to.equal(2)
				connection1:Disconnect()
				connection2:Disconnect()
			end)
		end)
	end)
end