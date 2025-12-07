--[[
Copyright (c) 2025 LiquidPane

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

--!strict
local RunService = game:GetService("RunService")

local IS_CLIENT = RunService:IsClient()

export type SerializationTable = {
	[number]: {
		write: (buffer, number, any) -> (),
		read: (buffer, number) -> any,
		getSize: (any) -> number,
	},
}

type Args = { [number]: any, ["n"]: number }

local function serialize(args: Args, serializationTable: SerializationTable): buffer
	local size = 0
	for i = 1, #args do
		local v = args[i]
		size += serializationTable[i].getSize(v)
	end

	local buff = buffer.create(size)

	local lastOffset = 0
	for i = 1, #args do
		local v = args[i]

		local method = serializationTable[i].write

		method(buff, lastOffset, v)
		lastOffset = i * serializationTable[i].getSize(v)
	end

	return buff
end

local function deserialize(buff: buffer, serializationTable: SerializationTable)
	local args = {}

	local lastOffset = 0
	for i, v in serializationTable do
		local method = v.read

		args[i] = method(buff, lastOffset)
		lastOffset = i * serializationTable[i].getSize(args[i])
	end

	return args
end

local ServerRemote = {}
ServerRemote.__index = ServerRemote

function ServerRemote:fireClient(player: Player, ...)
	local args: Args = table.pack(...)
	local buff = serialize(args, self._serializationTable)

	self._remoteEvent:FireClient(player, buff)
end

function ServerRemote:fireClients(players: {[number]: Player}, ...)
	local args: Args = table.pack(...)
	local buff = serialize(args, self._serializationTable)
	
	for _, player in players do
		self._remoteEvent:FireClient(player, buff)
	end
end

function ServerRemote:fireAllClients(...)
	local args: Args = table.pack(...)
	local buff = serialize(args, self._serializationTable)

	self._remoteEvent:FireAllClients(buff)
end

function ServerRemote:connect(callback: (Player, any) -> ()): RBXScriptConnection
	local connection = self._remoteEvent.OnServerEvent:Connect(function(player: Player, buff: buffer)
		local args = deserialize(buff, self._serializationTable)
		callback(player, table.unpack(args))
	end)

	table.insert(self._connections, connection)

	return connection
end

function ServerRemote:destroy()
	script[self._tag]:Destroy()

	for _, v in self._connections :: { [number]: RBXScriptConnection } do
		v:Disconnect()
	end

	table.clear(self)
end

local ClientRemote = {}
ClientRemote.__index = ClientRemote

function ClientRemote:fireServer(...)
	local args: Args = table.pack(...)

	local buff = serialize(args, self._serializationTable)
	self._remoteEvent:FireServer(buff)
end

function ClientRemote:connect(callback: (Player, any) -> ()): RBXScriptConnection
	return self._remoteEvent.OnClientEvent:Connect(function(buff: buffer)
		local args = deserialize(buff, self._serializationTable)
		callback(table.unpack(args))
	end)
end

function ClientRemote:destroy()
	script[self._tag]:Destroy()

	for _, v in self._connections :: { [number]: RBXScriptConnection } do
		v:Disconnect()
	end

	table.clear(self)
end

local LiquidNetwork = {}

function LiquidNetwork.createClient(tag: string, serializationTable: SerializationTable)
	local remoteEvent = script:WaitForChild(tag)

	local self = {
		_tag = tag,
		_serializationTable = serializationTable,
		_remoteEvent = remoteEvent,
		_connections = {},
	}

	return setmetatable(self, ClientRemote)
end

function LiquidNetwork.createServer(tag: string, serializationTable: SerializationTable)
	local remoteEvent = script:FindFirstChild(tag)
	if not remoteEvent then
		remoteEvent = Instance.new("RemoteEvent")
	end

	remoteEvent.Name = tag
	remoteEvent.Parent = script

	local self = {
		_tag = tag,
		_serializationTable = serializationTable,
		_remoteEvent = remoteEvent,
		_connections = {},
	}

	return setmetatable(self, ServerRemote)
end

function LiquidNetwork.createCustomType(
	write: (buffer, number, any) -> (),
	read: (buffer, number) -> any,
	getSize: (any) -> number
)
	return table.freeze({
		write = write,
		read = read,
		getSize = getSize,
	})
end

LiquidNetwork.boolean = table.freeze({
	write = function(buff: buffer, offset: number, value: boolean)
		buffer.writeu8(buff, offset, if value then 1 else 0)
	end,
	read = function(buff: buffer, offset: number)
		return if buffer.readu8(buff, offset) == 1 then true else false
	end,
	getSize = function(_): number
		return 1
	end,
})

LiquidNetwork.uint8 = table.freeze({
	write = buffer.writeu8,
	read = buffer.readu8,
	getSize = function(_): number
		return 1
	end,
})

LiquidNetwork.uint16 = table.freeze({
	write = buffer.writeu16,
	read = buffer.readu16,
	getSize = function(_): number
		return 2
	end,
})

LiquidNetwork.uint32 = table.freeze({
	write = buffer.writeu32,
	read = buffer.readu32,
	getSize = function(_): number
		return 4
	end,
})

LiquidNetwork.int8 = table.freeze({
	write = buffer.writei8,
	read = buffer.readi8,
	getSize = function(_): number
		return 1
	end,
})

LiquidNetwork.int16 = table.freeze({
	write = buffer.writei16,
	read = buffer.readi16,
	getSize = function(_): number
		return 2
	end,
})

LiquidNetwork.int32 = table.freeze({
	write = buffer.writei32,
	read = buffer.readi32,
	getSize = function(_): number
		return 4
	end,
})

LiquidNetwork.float = table.freeze({
	write = buffer.writef32,
	read = buffer.readf32,
	getSize = function(_): number
		return 4
	end,
})

LiquidNetwork.double = table.freeze({
	write = buffer.writef64,
	read = buffer.readf64,
	getSize = function(_): number
		return 8
	end,
})

LiquidNetwork.vector3 = table.freeze({
	write = function(buff: buffer, offset: number, value: Vector3)
		buffer.writef32(buff, offset, value.X)
		buffer.writef32(buff, offset + 4, value.Y)
		buffer.writef32(buff, offset + 8, value.Z)
	end,

	read = function(buff: buffer, offset: number): Vector3
		local x = buffer.readf32(buff, offset)
		local y = buffer.readf32(buff, offset + 4)
		local z = buffer.readf32(buff, offset + 8)

		return Vector3.new(x, y, z)
	end,

	getSize = function(_): number
		return 12
	end,
})

LiquidNetwork.cframe = table.freeze({
	write = function(buff: buffer, offset: number, value: CFrame)
		local v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11 = value:GetComponents()
		buffer.writef32(buff, offset, v0)
		buffer.writef32(buff, offset + 4, v1)
		buffer.writef32(buff, offset + 8, v2)
		buffer.writef32(buff, offset + 12, v3)
		buffer.writef32(buff, offset + 16, v4)
		buffer.writef32(buff, offset + 20, v5)
		buffer.writef32(buff, offset + 24, v6)
		buffer.writef32(buff, offset + 28, v7)
		buffer.writef32(buff, offset + 32, v8)
		buffer.writef32(buff, offset + 36, v9)
		buffer.writef32(buff, offset + 40, v10)
		buffer.writef32(buff, offset + 44, v11)
	end,

	read = function(buff: buffer, offset: number): CFrame
		return CFrame.new(
			buffer.readf32(buff, offset),
			buffer.readf32(buff, offset + 4),
			buffer.readf32(buff, offset + 8),
			buffer.readf32(buff, offset + 12),
			buffer.readf32(buff, offset + 16),
			buffer.readf32(buff, offset + 20),
			buffer.readf32(buff, offset + 24),
			buffer.readf32(buff, offset + 28),
			buffer.readf32(buff, offset + 32),
			buffer.readf32(buff, offset + 36),
			buffer.readf32(buff, offset + 40),
			buffer.readf32(buff, offset + 44)
		)
	end,

	getSize = function(_): number
		return 48
	end,
})

LiquidNetwork.lossyCFrame = table.freeze({
	write = function(buff: buffer, offset: number, value: CFrame)
		local axis, angle = value:ToAxisAngle()
		buffer.writef32(buff, offset, value.X)
		buffer.writef32(buff, offset + 4, value.Y)
		buffer.writef32(buff, offset + 8, value.Z)
		buffer.writef32(buff, offset + 12, axis.X)
		buffer.writef32(buff, offset + 16, axis.Y)
		buffer.writef32(buff, offset + 20, axis.Z)
		buffer.writef32(buff, offset + 24, angle)
	end,

	read = function(buff: buffer, offset: number): CFrame
		local angle = buffer.readf32(buff, offset + 24)
		local axis = Vector3.new(
			buffer.readf32(buff, offset + 12),
			buffer.readf32(buff, offset + 16),
			buffer.readf32(buff, offset + 20)
		)
		local position = Vector3.new(
			buffer.readf32(buff, offset),
			buffer.readf32(buff, offset + 4),
			buffer.readf32(buff, offset + 8)
		)

		return CFrame.fromAxisAngle(axis, angle) + position
	end,

	getSize = function(_): number
		return 28
	end,
})

LiquidNetwork.string8 = table.freeze({
	write = function(buff: buffer, offset: number, value: string)
		local length = string.len(value)

		buffer.writeu8(buff, offset, length)
		buffer.writestring(buff, offset + 1, value)
	end,

	read = function(buff: buffer, offset: number): string
		local length = buffer.readu8(buff, offset)

		return buffer.readstring(buff, offset + 1, length)
	end,

	getSize = function(value: string): number
		return 1 + string.len(value)
	end,
})

LiquidNetwork.string16 = table.freeze({
	write = function(buff: buffer, offset: number, value: string)
		local length = string.len(value)

		buffer.writeu16(buff, offset, length)
		buffer.writestring(buff, offset + 2, value)
	end,

	read = function(buff: buffer, offset: number): string
		local length = buffer.readu16(buff, offset)

		return buffer.readstring(buff, offset + 2, length)
	end,

	getSize = function(value: string): number
		return 2 + string.len(value)
	end,
})

LiquidNetwork.string32 = table.freeze({
	write = function(buff: buffer, offset: number, value: string)
		local length = string.len(value)

		buffer.writeu32(buff, offset, length)
		buffer.writestring(buff, offset + 4, value)
	end,

	read = function(buff: buffer, offset: number): string
		local length = buffer.readu32(buff, offset)

		return buffer.readstring(buff, offset + 4, length)
	end,

	getSize = function(value: string): number
		return 4 + string.len(value)
	end,
})

return LiquidNetwork
