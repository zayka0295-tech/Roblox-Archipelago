-- Гибель корабля (авианосец, линкор/катер/подлодка, грузовое судно): серия взрывов по палубе,
-- затем крен на борт и медленное погружение до floor (или timeout). Одна реализация на всех —
-- раньше этот код был скопирован в CarrierService, ShipService и LogisticsService.
-- Вызывать внутри task.spawn: функция ждёт, пока корабль утонет.
-- Возвращает false, если модель исчезла во время взрывов (тогда тонуть нечему).
local SinkFx = {}

-- o: explosions, radius, width, length, height — взрывы в прямоугольнике палубы width × length на высоте height;
--    ao, lv, root, yaw — управление корпусом (AlignOrientation, LinearVelocity, корень, курс);
--    pitch, roll (°), speed (студ/с вниз), floor (Y дна), timeout (сек.), noCollide — сквозь дно без столкновений
function SinkFx.run(m, o)
	for _ = 1, o.explosions do
		if not m.Parent then return false end
		local e = Instance.new("Explosion")
		e.BlastPressure = 0
		e.DestroyJointRadiusPercent = 0
		e.BlastRadius = o.radius
		e.Position = (m:GetPivot() * CFrame.new((math.random() - 0.5) * o.width, o.height or 6, (math.random() - 0.5) * o.length)).Position
		e.Parent = workspace
		task.wait(0.35)
	end
	if not m.Parent then return false end
	if not (o.ao and o.lv and o.root) then return true end
	if o.noCollide then
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide = false end
		end
	end
	o.ao.Responsiveness = 2
	o.ao.CFrame = CFrame.Angles(0, o.yaw or 0, 0) * CFrame.Angles(math.rad(o.pitch or 10), 0, math.rad(o.roll or 22))
	o.lv.VectorVelocity = Vector3.new(0, -(o.speed or 3.5), 0)
	local t0 = os.clock()
	while m.Parent and o.root.Position.Y > o.floor and os.clock() - t0 < o.timeout do
		task.wait(0.5)
	end
	return true
end

return SinkFx
