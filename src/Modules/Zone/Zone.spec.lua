local Players = game:GetService("Players")

return function()
    local Zone = require(script.Parent)

	local part = Instance.new("Part")
	part.Size = Vector3.new(50, 50, 50)
	part.Position = Vector3.new(100, 100, 100)
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = true
	part.Anchored = true
	part.Transparency = 0.8
	part.Parent = workspace

	local character = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()

    describe("zone", function()
		it("should create a new zone", function()
			local zone = Zone.new(part)
			zone:enable()
			expect(zone).to.be.ok()
			expect(zone.className).to.equal("Zone")
		end)
		it("should detect players added", function()
			local zone = Zone.new(part)
			zone:enable()
			character:PivotTo(part.CFrame)
			task.delay(1, function()
				local detected = zone:getDetectedPlayers()
				expect(#detected).to.be.equal(1)
			end)
		end)
		it("should detect players removed", function()
			local zone = Zone.new(part, 0.1)
			zone:enable()
			character:PivotTo(part.CFrame)
			task.wait(1)
			character:PivotTo(CFrame.new(Vector3.new(0, 5, 0)))
			task.delay(1, function()
				local detected = zone:getDetectedPlayers()
				expect(#detected).to.be.equal(0)
			end)
		end)
		it("should call added event when player is added", function()
			local zone = Zone.new(part, 0.1)
			zone:enable()
			local playerAdded = false
			local connection = zone.playerAdded:connect(function(player)
				playerAdded = true
			end)
			character:PivotTo(part.CFrame)
			task.delay(1, function()
				expect(playerAdded).to.be.equal(true)
				connection:disconnect()
			end)
		end)
		it("should call removed event when player is removed", function()
			local zone = Zone.new(part, 0.1)
			zone:enable()
			local playerRemoved = false
			local connection = zone.playerRemoved:connect(function(player)
				playerRemoved = true
			end)
			character:PivotTo(part.CFrame)
			task.wait(1)
			character:PivotTo(CFrame.new(Vector3.new(0, 5, 0)))
			task.delay(1, function()
				expect(playerRemoved).to.be.equal(true)
				connection:disconnect()
			end)
		end)
		it("should call detected event when player is detected", function()
			local zone = Zone.new(part, 0.1)
			zone:enable()
			local playerDetected = false
			local connection = zone.detected:connect(function(player)
				playerDetected = true
			end)
			character:PivotTo(part.CFrame)
			task.delay(1, function()
				expect(playerDetected).to.be.equal(true)
				connection:disconnect()
			end)
		end)
    end)
end