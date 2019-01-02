local ui_get, ui_set = ui.get, ui.set
local screen_width, screen_height = client.screen_size()

local menu = {
    is_active = ui.new_checkbox("AA", "Other", "Desync anti-aim"),
    threat = ui.new_checkbox("AA", "Other", "Strict enemy checks"),
    hide_elems = ui.new_checkbox("AA", "Other", "Hide elements"),

    arrows = ui.new_multiselect("AA", "Other", "Direction arrows", { "Triangles", "Lines" }),
    picker = ui.new_color_picker("AA", "Other", "Arrows picker", 27, 255, 200, 150),

    left = ui.new_hotkey("AA", "Other", "Desync left"),
    right = ui.new_hotkey("AA", "Other", "Desync right"),
}

local aa_yaw, aa_num = ui.reference("AA", "Anti-aimbot angles", "Yaw")
local aa_jitter, aa_jitter_range = ui.reference("AA", "Anti-aimbot angles", "Yaw jitter")
local aa_run = ui.reference("AA", "Anti-aimbot angles", "Yaw while running")
local aa_fake, aa_fake_num = ui.reference("AA", "Anti-aimbot angles", "Fake yaw")
local aa_update = ui.reference("AA", "Anti-aimbot angles", "Always update fake yaw")

local isLeft, isRight, n = false, false, 0
local lstate, rstate = ui_get(menu.left), ui_get(menu.right)

function update_bind_state()
    ui_set(menu.left, "Toggle")
    ui_set(menu.right, "Toggle")

    if (ui_get(menu.left) ~= lstate and n == 1) or (ui_get(menu.right) ~= rstate and n == 2) then
        lstate, rstate = ui_get(menu.left), ui_get(menu.right)
        isRight, isLeft, n = false, false, 0
        return
    end

    if ui_get(menu.left) ~= lstate then
        lstate = ui_get(menu.left)
        isRight, isLeft, n = false, true, 1
    end

    if ui_get(menu.right) ~= rstate then
        rstate = ui_get(menu.right)
        isRight, isLeft, n = true, false, 2
    end
end

function table_state(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

function round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
  end

function is_thirdperson(c)
	local x, y, z = client.eye_position()
	local pitch, yaw = client.camera_angles()
	
	yaw = yaw - 180
	pitch, yaw = math.rad(pitch), math.rad(yaw)

	x = x + math.cos(yaw)*4
	y = y + math.sin(yaw)*4
	z = z + math.sin(pitch)*4

	local wx, wy = client.world_to_screen(c, x, y, z)
	return wx ~= nil
end

function draw_angle(c, name, distance, location_x, location_y, location_z, origin_x, origin_y, yaw, r, g, b, a)
	local location_x_angle = location_x + math.cos(math.rad(yaw)) * distance
	local location_y_angle = location_y + math.sin(math.rad(yaw)) * distance

	local world_x, world_y = client.world_to_screen(c, location_x_angle, location_y_angle, location_z)

	if world_x ~= nil then
		client.draw_line(c, origin_x, origin_y, world_x, world_y, r, g, b, 220)
		client.draw_text(c, world_x, world_y, r, g, b, a, "c-", 0, name)
	end
end

function calc_angle(x_src, y_src, z_src, x_dst, y_dst, z_dst)
    x_delta = x_src - x_dst
    y_delta = y_src - y_dst
    z_delta = z_src - z_dst
    hyp = math.sqrt(x_delta^2 + y_delta^2)
    x = math.atan2(z_delta, hyp) * 57.295779513082
    y = math.atan2( y_delta , x_delta) * 180 / 3.14159265358979323846

    if y > 180 then
        y = y - 180
    end
    if y < -180 then
        y = y + 180
    end
    return y
end

function normalize_angles(angle)
    angle = angle % 360 
    angle = (angle + 360) % 360
    if (angle > 180)  then
        angle = angle - 360
    end

    return angle
end

function get_near_target()
	local enemy_players = entity.get_players(true)
	if #enemy_players ~= 0 then
		local own_x, own_y, own_z = client.eye_position()
		local own_pitch, own_yaw = client.camera_angles()
		local closest_enemy = nil
		local closest_distance = 999999999
		        
		for i = 1, #enemy_players do
			local enemy = enemy_players[i]
			local enemy_x, enemy_y, enemy_z = entity.get_prop(enemy, "m_vecOrigin")
		            
			local x = enemy_x - own_x
			local y = enemy_y - own_y
			local z = enemy_z - own_z 

			local yaw = ((math.atan2(y, x) * 180 / math.pi))
			local pitch = -(math.atan2(z, math.sqrt(math.pow(x, 2) + math.pow(y, 2))) * 180 / math.pi)

			local yaw_dif = math.abs(own_yaw % 360 - yaw % 360) % 360
			local pitch_dif = math.abs(own_pitch - pitch ) % 360
	            
			if yaw_dif > 180 then yaw_dif = 360 - yaw_dif end
			local real_dif = math.sqrt(math.pow(yaw_dif, 2) + math.pow(pitch_dif, 2))

			if closest_distance > real_dif then
				closest_distance = real_dif
				closest_enemy = enemy
			end
		end

		if closest_enemy ~= nil then
			return closest_enemy, closest_distance
		end
	end

	return nil, nil
end

client.set_event_callback("paint", function(c)
    if not ui_get(menu.is_active) then
        return
    end

    menu_listener()
    update_bind_state()
    
    local is_targeting, angle = false, nil

    if isLeft then yaw_deg, jit_deg = 47, 90 end
    if isRight then yaw_deg, jit_deg = -150, 99 end

    g_pLocal = entity.get_local_player()
    local threat_id, threat_dist = get_near_target()

    if ui_get(menu.threat) and (threat_dist and threat_dist <= 15) then
        local x, y, z = entity.get_prop(g_pLocal, "m_vecOrigin")

        if x ~= nil then
            local ent_x, ent_y, ent_z = entity.hitbox_position(threat_id, 0)
            angle = calc_angle(x, y, z, ent_x, ent_y, ent_z) + 180

            if isLeft then
                angle = angle - 130
            elseif isRight then
                angle = angle + 31
            end

            ui_set(aa_yaw, "Static")
            ui_set(aa_num, normalize_angles(angle))
            is_targeting = true

            client.draw_text(c, 12, 700, 243, 125, 124, 255, "-", "200", "THREAT: ", string.upper(entity.get_player_name(threat_id)))
            client.draw_text(c, 12, 710, 255, 255, 255, 255, "-", "200", "DISTANCE: ", round(threat_dist, 0) .. " FT")
            client.draw_text(c, 12, 720, 255, 255, 255, 255, "-", "200", "ANGLE: ", round(angle, 1))
        end
    end

    if isLeft or isRight then
        if is_targeting and angle ~= nil then
            ui_set(aa_yaw, "Static")
            ui_set(aa_num, normalize_angles(angle))
        else
            ui_set(aa_yaw, "180")
            ui_set(aa_num, yaw_deg) 
        end

        ui_set(aa_jitter, "Offset")
        ui_set(aa_jitter_range, jit_deg)
        ui_set(aa_run, "Off")
        ui_set(aa_fake, "Crooked")
        ui_set(aa_update, true)
    else
        if is_targeting and angle ~= nil then
            ui_set(aa_yaw, "Static")
            ui_set(aa_num, normalize_angles((angle - 180) - 20))
        else
            ui_set(aa_yaw, "180")
            ui_set(aa_num, -20)
        end

        ui_set(aa_jitter, "Off")
        ui_set(aa_jitter_range, 0)
        ui_set(aa_run, "Off")
        ui_set(aa_fake, "180")
        ui_set(aa_fake_num, -25)
        ui_set(aa_update, true)
    end

    if  not entity.is_alive(g_pLocal) or #ui_get(menu.arrows) == 0 then 
        return
    end

    if table_state(ui_get(menu.arrows), "Triangles") then
        local r, g, b, a = ui_get(menu.picker)
        if not isLeft then r, g, b = 255, 255, 255 end
        renderer.text(screen_width / 2 - 70, screen_height / 2 - 14, r, g, b, a, "+", 0, "◄")

        local r, g, b = ui_get(menu.picker)
        if not isRight then r, g, b = 255, 255, 255 end
        renderer.text(screen_width / 2 + 50, screen_height / 2 - 14, r, g, b, a, "+", 0, "►")
    end

    if table_state(ui_get(menu.arrows), "Lines") and is_thirdperson(c) then
        local location_x, location_y, location_z = entity.get_prop(g_pLocal, "m_vecAbsOrigin")
        if location_x then

            local world_x, world_y = client.world_to_screen(c, location_x, location_y, location_z + 1)
            if world_x ~= nil then
                local _, yaw = entity.get_prop(g_pLocal, "m_angAbsRotation")
                if yaw ~= nil then
                    local bodyyaw = entity.get_prop(g_pLocal, "m_flPoseParameter", 11)
                    if bodyyaw ~= nil then
                        bodyyaw = bodyyaw * 120 - 60
                        draw_angle(c, "POS", 30, location_x, location_y, location_z + 1, world_x, world_y, yaw + bodyyaw, ui_get(menu.picker))
                    end
                end
    
                client.draw_circle(c, world_x, world_y, 17, 17, 17, 255, 2, 0, 1)
            end
            
        end
    end
end)

function menu_listener(data)
    if type(data) == "table" then
        for i = 1, #data, 1 do
            ui.set_callback(menu[data[i]], menu_listener)
        end
        return
    end

    local rpc = ui_get(menu.is_active)
    local hpc = ui_get(menu.hide_elems)
    local nhp = ui_get(menu.arrows)

    ui.set_visible(menu.threat, rpc)
    ui.set_visible(menu.hide_elems, rpc)
    ui.set_visible(menu.arrows, rpc)
    ui.set_visible(menu.picker, rpc)

    ui.set_visible(menu.left, rpc)
    ui.set_visible(menu.right, rpc)

    -- Hide menu
    ui.set_visible(aa_yaw, not (rpc and hpc))
    ui.set_visible(aa_num, not (rpc and hpc))
    ui.set_visible(aa_jitter, not (rpc and hpc))
    ui.set_visible(aa_jitter_range, not (rpc and hpc))
    ui.set_visible(aa_run, not (rpc and hpc))
    ui.set_visible(aa_update, not (rpc and hpc))
    ui.set_visible(aa_fake, not (rpc and hpc))
    ui.set_visible(aa_fake_num, not (rpc and hpc))
end

menu_listener({ "is_active", "hide_elems", "arrows" })
-- desync aa by Salvatore (idea by LcaL)