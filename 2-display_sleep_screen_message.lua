local Blitbuffer = require("ffi/blitbuffer")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local MovableContainer = require("ui/widget/container/movablecontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RenderImage = require("ui/renderimage")
local Screensaver = require("ui/screensaver")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TopContainer = require("ui/widget/container/topcontainer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Input = Device.input
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local SleepScreenMessage = InfoMessage:extend {
    icon = "sleep.screen.please",
    container_position = "center", -- or "top" or "bottom"
    -- Passed to TextBoxWidget
    alignment = "center",
}

function SleepScreenMessage:init()
    if not self.face then
        self.face = Font:getFace(self.monospace_font and "infont" or "infofont") --CUSTOM/TODO: change font
    end

    if self.dismissable then
        if Device:hasKeys() then
            self.key_events.AnyKeyPressed = { { Input.group.Any } }
        end
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new {
                    ges = "tap",
                    range = Geom:new {
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
    end

    local image_widget
    if self.show_icon then
        --- @todo remove self.image support, only used in filemanagersearch
        -- this requires self.image's lifecycle to be managed by ImageWidget
        -- instead of caller, which is easy to introduce bugs
        if self.image then
            image_widget = ImageWidget:new {
                image = self.image,
                width = self.image_width,
                height = self.image_height,
                alpha = self.alpha ~= nil and self.alpha or false, -- default to false
            }
        else
            image_widget = IconWidget:new {
                icon = self.icon,
                alpha = self.alpha == nil and true or self.alpha, -- default to true
            }
        end
    else
        image_widget = WidgetContainer:new()
    end

    local text_width
    if self.width == nil then
        text_width = math.floor(Screen:getWidth() * 2 / 3)
    else
        text_width = self.width - image_widget:getSize().w
        if text_width < 0 then
            text_width = 0
        end
    end

    local text_widget
    if self.height then
        text_widget = ScrollTextWidget:new {
            text = self.text,
            face = self.face,
            width = text_width,
            height = self.height,
            alignment = self.alignment,
            dialog = self,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
        }
    else
        text_widget = TextBoxWidget:new {
            text = self.text,
            face = self.face,
            width = text_width,
            alignment = self.alignment,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
        }
    end
    local frame = FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        VerticalGroup:new {
            align = "center",
            image_widget,
            HorizontalSpan:new { width = (self.show_icon and Size.span.horizontal_default or 0) },
            text_widget,
        }
    }
    self.movable = MovableContainer:new {
        frame,
        unmovable = self.unmovable,
    }

    --local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    if self.container_position == "center" then
        self[1] = CenterContainer:new {
            dimen = Screen:getSize(),
            self.movable,
        }
    elseif self.container_position == "top" then
        local topContainer = TopContainer:new {
            dimen = Screen:getSize(),
            self.movable,
        }

        topContainer.paintTo = function(self, bb, x, y)
            local contentSize = self[1]:getSize()
            self[1]:paintTo(bb,
                x + math.floor((self.dimen.w - contentSize.w) / 2),
                y)
        end

        self[1] = topContainer
    else
        self[1] = BottomContainer:new {
            dimen = Screen:getSize(),
            self.movable,
        }
    end

    if not self.height then
        local max_height
        if self.force_one_line and not self.text:find("\n") then
            local icon_height = self.show_icon and image_widget:getSize().h or 0
            -- Calculate the size of the frame container when it's only displaying one line.
            max_height = math.max(text_widget:getLineHeight(), icon_height) + 2 * frame.bordersize + 2 * frame.padding
        else
            max_height = Screen:getHeight() * 0.95
        end

        -- Reduce font size if the text is too long
        local cur_size = frame:getSize()
        if self.force_one_line and not (self._initial_orig_font and self._initial_orig_size) then
            self._initial_orig_font = text_widget.face.orig_font
            self._initial_orig_size = text_widget.face.orig_size
        end
        if cur_size and cur_size.h > max_height then
            local orig_font = text_widget.face.orig_font
            local orig_size = text_widget.face.orig_size
            local real_size = text_widget.face.size
            if orig_size > 10 then -- don't go too small
                while true do
                    orig_size = orig_size - 1
                    self.face = Font:getFace(orig_font, orig_size)
                    -- scaleBySize() in Font:getFace() may give the same
                    -- real font size even if we decreased orig_size,
                    -- so check we really got a smaller real font size
                    if self.face.size < real_size then
                        break
                    end
                end
                if self.force_one_line and orig_size < 16 then
                    -- Do not reduce the font size any longer, at around this point, our font is too small for the max_height check to be useful
                    -- anymore (when icon_height), at those sizes (or lower) two lines fit inside the max_height so, simply disable it.
                    self.face = Font:getFace(self._initial_orig_font, self._initial_orig_size)
                    self.force_one_line = false
                end
                -- re-init this widget
                self:free()
                self:init()
            end
        end
    end

    if self.show_delay then
        -- Don't have UIManager setDirty us yet
        self.invisible = true
    end
end

Screensaver.show = function(self)
    -- Notify Device methods that we're in screen saver mode, so they know whether to suspend or resume on Power events.
    Device.screen_saver_mode = true

    -- Check if we requested a lock gesture
    local with_gesture_lock = Device:isTouchDevice() and G_reader_settings:readSetting("screensaver_delay") == "gesture"

    -- In as-is mode with no message, no overlay and no lock, we've got nothing to show :)
    if self.screensaver_type == "disable" and not self.show_message and not self.overlay_message and not with_gesture_lock then
        return
    end

    local rotation_mode = Screen:getRotationMode()

    -- We mostly always suspend in Portrait/Inverted Portrait mode...
    -- ... except when we just show an InfoMessage or when the screensaver
    -- is disabled, as it plays badly with Landscape mode (c.f., #4098 and #5920).
    -- We also exclude full-screen widgets that work fine in Landscape mode,
    -- like ReadingProgress and BookStatus (c.f., #5724)
    if self:modeExpectsPortrait() then
        Device.orig_rotation_mode = rotation_mode
        -- Leave Portrait & Inverted Portrait alone, that works just fine.
        if bit.band(Device.orig_rotation_mode, 1) == 1 then
            -- i.e., only switch to Portrait if we're currently in *any* Landscape orientation (odd number)
            Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)
        else
            Device.orig_rotation_mode = nil
        end

        -- On eInk, if we're using a screensaver mode that shows an image,
        -- flash the screen to white first, to eliminate ghosting.
        if Device:hasEinkScreen() and self:modeIsImage() then
            if self:withBackground() then
                Screen:clear()
            end
            Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())

            -- On Kobo, on sunxi SoCs with a recent kernel, wait a tiny bit more to avoid weird refresh glitches...
            if Device:isKobo() and Device:isSunxi() then
                ffiUtil.usleep(150 * 1000)
            end
        end
    else
        -- nil it, in case user switched ScreenSaver modes during our lifetime.
        Device.orig_rotation_mode = nil
    end

    -- Build the main widget for the effective mode, all the sanity checks were handled in setup
    local widget = nil
    if self.screensaver_type == "cover" or self.screensaver_type == "random_image" then
        local widget_settings = {
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
            stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
        }
        if self.image then
            widget_settings.image = self.image
            widget_settings.image_disposable = true
        elseif self.image_file then
            if G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit") then
                -- We need to load the image here to determine whether to rotate
                if util.getFileNameSuffix(self.image_file) == "svg" then
                    widget_settings.image = RenderImage:renderSVGImageFile(self.image_file, nil, nil, 1)
                else
                    widget_settings.image = RenderImage:renderImageFile(self.image_file, false, nil, nil)
                end
                if not widget_settings.image then
                    widget_settings.image = RenderImage:renderCheckerboard(Screen:getWidth(), Screen:getHeight(),
                        Screen.bb:getType())
                end
                widget_settings.image_disposable = true
            else
                widget_settings.file = self.image_file
                widget_settings.file_do_cache = false
            end
            widget_settings.alpha = true
        end                                               -- set cover or file
        if G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit") then
            local angle = rotation_mode == 3 and 180 or 0 -- match mode if possible
            if (widget_settings.image:getWidth() < widget_settings.image:getHeight()) ~= (widget_settings.width < widget_settings.height) then
                angle = angle + (G_reader_settings:isTrue("imageviewer_rotation_landscape_invert") and -90 or 90)
            end
            widget_settings.rotation_angle = angle
        end
        widget = ImageWidget:new(widget_settings)
    elseif self.screensaver_type == "bookstatus" then
        local ReaderUI = require("apps/reader/readerui")
        widget = BookStatusWidget:new {
            ui = ReaderUI.instance,
            readonly = true,
        }
    elseif self.screensaver_type == "readingprogress" then
        widget = Screensaver.getReaderProgress()
    end

    -- Assume that we'll be covering the full-screen by default (either because of a widget, or a background fill).
    local covers_fullscreen = true
    -- Speaking of, set that background fill up...
    local background
    if self.screensaver_background == "black" then
        background = Blitbuffer.COLOR_BLACK
    elseif self.screensaver_background == "white" then
        background = Blitbuffer.COLOR_WHITE
    elseif self.screensaver_background == "none" then
        background = nil
    end

    local message_height
    if self.show_message then
        -- Handle user settings & fallbacks, with that prefix mess on top...
        local screensaver_message = self.default_screensaver_message

        if G_reader_settings:has(self.prefix .. "screensaver_message") then
            screensaver_message = G_reader_settings:readSetting(self.prefix .. "screensaver_message")
        elseif G_reader_settings:has("screensaver_message") then
            screensaver_message = G_reader_settings:readSetting("screensaver_message")
        end
        -- If the message is set to the defaults (which is also the case when it's unset), prefer the event message if there is one.
        if screensaver_message == self.default_screensaver_message then
            if self.event_message then
                screensaver_message = self.event_message
                -- The overlay is only ever populated with the event message, and we only want to show it once ;).
                self.overlay_message = nil
            end
        end

        -- NOTE: Only attempt to expand if there are special characters in the message.
        if screensaver_message:find("%%") then
            screensaver_message = self:expandSpecial(screensaver_message,
                self.event_message or self.default_screensaver_message)
        end

        local message_pos
        if G_reader_settings:has(self.prefix .. "screensaver_message_position") then
            message_pos = G_reader_settings:readSetting(self.prefix .. "screensaver_message_position")
        else
            message_pos = G_reader_settings:readSetting("screensaver_message_position")
        end

        -- The only case where we *won't* cover the full-screen is when we only display a message and no background.
        if widget == nil and self.screensaver_background == "none" then
            covers_fullscreen = false
        end

        local message_widget

        -- CUSTOM: jump lines by using "\n"
        screensaver_message = screensaver_message:gsub("\\n", "\n")

        -- CUSTOM: use of SleepScreenMessage
        if message_pos == "bottom" then
            SleepScreenMessage.container_position = "bottom"
        elseif message_pos == "top" then
            SleepScreenMessage.container_position = "top"
        else
            SleepScreenMessage.container_position = "center"
        end

        message_widget = SleepScreenMessage:new {
            text = screensaver_message,
            readonly = true,
            dismissable = false,
        }

        -- Forward the height of the top message to the overlay widget
        if message_pos == "top" then
            message_height = message_widget[1]:getSize().h
        end

        -- Check if message_widget should be overlaid on another widget
        if message_widget then
            if widget then -- We have a Screensaver widget
                -- Show message_widget on top of previously created widget
                widget = OverlapGroup:new {
                    dimen = {
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    },
                    widget,
                    message_widget,
                }
            else
                -- No previously created widget, so just show message widget
                widget = message_widget
            end
        end
    end

    if self.overlay_message then
        widget = addOverlayMessage(widget, message_height, self.overlay_message)
    end

    -- NOTE: Make sure InputContainer gestures are not disabled, to prevent stupid interactions with UIManager on close.
    UIManager:setIgnoreTouchInput(false)

    if widget then
        self.screensaver_widget = ScreenSaverWidget:new {
            widget = widget,
            background = background,
            covers_fullscreen = covers_fullscreen,
        }
        self.screensaver_widget.modal = true
        self.screensaver_widget.dithered = true

        UIManager:show(self.screensaver_widget, "full")
    end

    -- Setup the gesture lock through an additional invisible widget, so that it works regardless of the configuration.
    if with_gesture_lock then
        self.screensaver_lock_widget = ScreenSaverLockWidget:new {}

        -- It's flagged as modal, so it'll stay on top
        UIManager:show(self.screensaver_lock_widget)
    end
end
