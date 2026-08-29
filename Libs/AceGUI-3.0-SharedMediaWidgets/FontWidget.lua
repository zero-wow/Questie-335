-- Widget is based on the AceGUIWidget-DropDown.lua supplied with AceGUI-3.0
-- Widget created by Yssaril

local AceGUI = LibStub("AceGUI-3.0")
local Media = LibStub("LibSharedMedia-3.0")

local AGSMW = LibStub("AceGUISharedMediaWidgets-1.0")

do
	local widgetType = "LSM30_Font"
	local widgetVersion = 14
	local CONTROL_MIN_WIDTH = 360
	local CONTROL_MAX_SCREEN_MARGIN = 120
	local DROPDOWN_MIN_WIDTH = 360
	local DROPDOWN_EXTRA_WIDTH = 160
	local DROPDOWN_TEXT_PADDING = 110
	local DROPDOWN_MAX_SCREEN_MARGIN = 24
	local SEARCH_RIGHT_PADDING = 34
	local SEARCH_PLACEHOLDER = "SEARCH..."
	local SEARCH_BACKDROP = {
		bgFile = [[Interface\Buttons\WHITE8X8]],
		edgeFile = [[Interface\Buttons\WHITE8X8]],
		tile = true,
		tileSize = 1,
		edgeSize = 1,
		insets = {
			left = 1,
			right = 1,
			top = 1,
			bottom = 1,
		},
	}
	local SEARCH_BG_COLOR = { 0.05, 0.07, 0.08, 0.96 }
	local SEARCH_BORDER_COLOR = { 0.09, 0.78, 0.70, 1.0 }
	local SEARCH_PLACEHOLDER_COLOR = { 0.52, 0.86, 0.79, 0.82 }
	local SEARCH_TEXT_COLOR = { 1.0, 1.0, 1.0, 1.0 }
	local SEARCH_CLEAR_COLOR = { 0.88, 0.96, 0.94, 0.72 }
	local SEARCH_CLEAR_HOVER_COLOR = { 1.0, 1.0, 1.0, 1.0 }
	local UpdateVisibleControlWidth
	local listMeasurementCache = setmetatable({}, { __mode = "k" })

	local function GetTrackerFonts()
		if QuestieLoader and QuestieLoader.ImportModule then
			return QuestieLoader:ImportModule("TrackerFonts")
		end
	end

	local function ResolveFont(self, key)
		local trackerFonts = GetTrackerFonts()
		if trackerFonts and trackerFonts.GetFontPathByName then
			return trackerFonts:GetFontPathByName(key)
		end

		local font = self.list and self.list[key]
		if font and font ~= key then
			return font
		end

		return Media:Fetch("font", key) or "Fonts\\FRIZQT__.TTF"
	end

	local contentFrameCache = {}
	local function ReturnSelf(self)
		self:ClearAllPoints()
		self:Hide()
		self.check:Hide()
		table.insert(contentFrameCache, self)
	end

	local function ContentOnClick(this, button)
		local self = this.obj
		self:Fire("OnValueChanged", this.text:GetText())
		if self.dropdown then
			self.dropdown = AGSMW:ReturnDropDownFrame(self.dropdown)
		end
	end

	local function GetContentLine()
		local frame
		if next(contentFrameCache) then
			frame = table.remove(contentFrameCache)
		else
			frame = CreateFrame("Button", nil, UIParent)
				--frame:SetWidth(200)
				frame:SetHeight(18)
				frame:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
				frame:SetScript("OnClick", ContentOnClick)
			local check = frame:CreateTexture("OVERLAY")
				check:SetWidth(16)
				check:SetHeight(16)
				check:SetPoint("LEFT",frame,"LEFT",1,-1)
				check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
				check:Hide()
			frame.check = check
			local text = frame:CreateFontString(nil,"OVERLAY","GameFontWhite")
				text:SetPoint("TOPLEFT", check, "TOPRIGHT", 4, 0)
				text:SetPoint("BOTTOMLEFT", check, "BOTTOMRIGHT", 4, 0)
				text:SetJustifyH("LEFT")
				if text.SetWordWrap then
					text:SetWordWrap(false)
				end
				if text.SetNonSpaceWrap then
					text:SetNonSpaceWrap(false)
				end
				text:SetText("Test Test Test Test Test Test Test")
			frame.text = text
			frame.UpdateWidth = function(self, width)
				local measuredWidth = 0
				if self.text.GetUnboundedStringWidth then
					measuredWidth = self.text:GetUnboundedStringWidth() or 0
				else
					measuredWidth = self.text:GetStringWidth() or 0
				end

				self:SetWidth(math.max(tonumber(width) or 0, math.ceil(measuredWidth + 28)))
			end
			frame.ReturnSelf = ReturnSelf
		end
		frame:Show()
		return frame
	end

	local function OnAcquire(self)
		self:SetHeight(44)
		self:SetWidth(CONTROL_MIN_WIDTH)
	end

	local function OnRelease(self)
		self:SetText("")
		self:SetLabel("")
		self:SetDisabled(false)

		self.value = nil
		self.list = nil
		self.open = nil
		self.hasClose = nil

		self.frame:ClearAllPoints()
		self.frame:Hide()
	end

	local function SetValue(self, value) -- Set the value to an item in the List.
		if self.list then
			self:SetText(value or "")
		end
		self.value = value
	end

	local function GetValue(self)
		return self.value
	end

	local function SetList(self, list) -- Set the list of values for the dropdown (key => value pairs)
		self.list = list or Media:HashTable("font")
		UpdateVisibleControlWidth(self)
	end

	local function SetText(self, text) -- Set the text displayed in the box.
		self.frame.text:SetText(text or "")
		local font = ResolveFont(self, text)
		local _, size, outline= self.frame.text:GetFont()
		self.frame.text:SetFont(font,size,outline)
	end

	local function SetLabel(self, text) -- Set the text for the label.
		self.frame.label:SetText(text or "")
	end

	local function AddItem(self, key, value) -- Add an item to the list.
		self.list = self.list or {}
		self.list[key] = value
	end
	local SetItemValue = AddItem -- Set the value of a item in the list. <<same as adding a new item>>

	local function SetMultiselect(self, flag) end -- Toggle multi-selecting. <<Dummy function to stay inline with the dropdown API>>
	local function GetMultiselect() return false end-- Query the multi-select flag. <<Dummy function to stay inline with the dropdown API>>
	local function SetItemDisabled(self, key) end-- Disable one item in the list. <<Dummy function to stay inline with the dropdown API>>

	local function SetDisabled(self, disabled) -- Disable the widget.
		self.disabled = disabled
		if disabled then
			self.frame:Disable()
		else
			self.frame:Enable()
		end
	end

	local function textSort(a,b)
		return string.upper(a) < string.upper(b)
	end

	local sortedlist = {}
	local measureFrame = CreateFrame("Frame", nil, UIParent)
	measureFrame:Hide()
	local measureText = measureFrame:CreateFontString(nil, "OVERLAY", "GameFontWhite")

	local function GetSafeUnboundedStringWidth(fontString)
		if not fontString then
			return 0
		end

		if fontString.GetUnboundedStringWidth then
			return fontString:GetUnboundedStringWidth() or 0
		end

		if QuestieCompat and QuestieCompat.GetUnboundedStringWidth then
			return QuestieCompat.GetUnboundedStringWidth(fontString) or 0
		end

		return fontString:GetStringWidth() or 0
	end

	local function GetFilteredKeys(self, filterText)
		local trackerFonts = GetTrackerFonts()
		if trackerFonts then
			if self.list == trackerFonts:GetValues() then
				return trackerFonts:GetOrderedNames(filterText, false)
			end
			if self.list == trackerFonts:GetOverrideValues() then
				return trackerFonts:GetOrderedNames(filterText, true)
			end
		end

		wipe(sortedlist)
		local loweredFilter = filterText and string.lower(filterText) or nil
		for key in pairs(self.list) do
			if not loweredFilter or loweredFilter == "" or string.find(string.lower(key), loweredFilter, 1, true) then
				sortedlist[#sortedlist + 1] = key
			end
		end
		table.sort(sortedlist, textSort)
		return sortedlist
	end

	local function GetListCacheState(self)
		if not self or not self.list then
			return nil, nil
		end

		local trackerFonts = GetTrackerFonts()
		if trackerFonts and trackerFonts.GetCacheVersion then
			if self.list == trackerFonts:GetValues() or self.list == trackerFonts:GetOverrideValues() then
				return listMeasurementCache[self.list], trackerFonts:GetCacheVersion()
			end
		end

		return listMeasurementCache[self.list], false
	end

	local function GetMeasuredTextWidth(self, key, cacheEntry)
		if cacheEntry and cacheEntry.widths and cacheEntry.widths[key] then
			return cacheEntry.widths[key]
		end

		local _, size, outline = measureText:GetFont()
		measureText:SetFont(ResolveFont(self, key), size, outline)
		measureText:SetText(key)
		local measuredWidth = GetSafeUnboundedStringWidth(measureText)

		if cacheEntry then
			cacheEntry.widths = cacheEntry.widths or {}
			cacheEntry.widths[key] = measuredWidth
		end

		return measuredWidth
	end

	local function BuildMeasurementCache(list, orderedKeys, version)
		if not list or not orderedKeys then
			return nil
		end

		local cacheEntry = {
			version = version,
			widths = {},
		}
		local pseudoWidget = {
			list = list,
		}
		local maxTextWidth = 0

		for _, key in ipairs(orderedKeys) do
			maxTextWidth = math.max(maxTextWidth, GetMeasuredTextWidth(pseudoWidget, key, cacheEntry))
		end

		cacheEntry.maxTextWidth = maxTextWidth
		listMeasurementCache[list] = cacheEntry
		return cacheEntry
	end

	local function GetMaxTextWidth(self, filteredKeys, filterText)
		local useCache = not filterText or filterText == ""
		local cacheEntry, cacheVersion = GetListCacheState(self)

		if useCache and cacheEntry and cacheEntry.version == cacheVersion and cacheEntry.maxTextWidth then
			return cacheEntry.maxTextWidth
		end

		if useCache and (not cacheEntry or cacheEntry.version ~= cacheVersion) then
			cacheEntry = {
				version = cacheVersion,
				widths = {},
			}
			listMeasurementCache[self.list] = cacheEntry
		end

		local maxTextWidth = 0
		for _, key in ipairs(filteredKeys) do
			maxTextWidth = math.max(maxTextWidth, GetMeasuredTextWidth(self, key, useCache and cacheEntry or nil))
		end

		if useCache and cacheEntry then
			cacheEntry.maxTextWidth = maxTextWidth
		end

		return maxTextWidth
	end

	function AGSMW:PrewarmTrackerFontMeasurements()
		local trackerFonts = GetTrackerFonts()
		if not (trackerFonts and trackerFonts.GetCacheVersion and trackerFonts.GetValues and trackerFonts.GetOverrideValues and trackerFonts.GetOrderedNames) then
			return
		end

		local cacheVersion = trackerFonts:GetCacheVersion()
		local values = trackerFonts:GetValues()
		local overrideValues = trackerFonts:GetOverrideValues()
		local valuesEntry = listMeasurementCache[values]
		local overrideEntry = listMeasurementCache[overrideValues]

		if not valuesEntry or valuesEntry.version ~= cacheVersion then
			BuildMeasurementCache(values, trackerFonts:GetOrderedNames(nil, false), cacheVersion)
		end

		if not overrideEntry or overrideEntry.version ~= cacheVersion then
			BuildMeasurementCache(overrideValues, trackerFonts:GetOrderedNames(nil, true), cacheVersion)
		end
	end

	local function GetPopupWidth(self, filteredKeys, filterText)
		local popupWidth = math.max(DROPDOWN_MIN_WIDTH, self.frame:GetWidth() + DROPDOWN_EXTRA_WIDTH)
		local maxTextWidth = GetMaxTextWidth(self, filteredKeys, filterText)

		if maxTextWidth > 0 then
			popupWidth = math.max(popupWidth, math.ceil(maxTextWidth + DROPDOWN_TEXT_PADDING))
		end

		local availableWidth = (UIParent and UIParent:GetWidth()) or GetScreenWidth() or popupWidth
		return math.min(popupWidth, math.max(DROPDOWN_MIN_WIDTH, availableWidth - DROPDOWN_MAX_SCREEN_MARGIN))
	end

	function UpdateVisibleControlWidth(self)
		if (not self) or (not self.frame) or (not self.list) then
			return
		end

		local filteredKeys = GetFilteredKeys(self, nil)
		local desiredWidth = GetPopupWidth(self, filteredKeys, nil)
		local availableWidth = (UIParent and UIParent:GetWidth()) or GetScreenWidth() or desiredWidth
		local controlWidth = math.max(CONTROL_MIN_WIDTH, math.min(desiredWidth, availableWidth - CONTROL_MAX_SCREEN_MARGIN))

		if self.SetWidth then
			self:SetWidth(controlWidth)
		else
			self.frame:SetWidth(controlWidth)
		end
	end

	local function ApplyDropdownWidth(dropdown, width)
		dropdown:ClearAllPoints()
		dropdown:SetPoint("TOPLEFT", dropdown.ownerFrame, "BOTTOMLEFT")
		dropdown:SetWidth(width)
	end

	local function PopulateDropdown(self, filterText)
		local filteredKeys = GetFilteredKeys(self, filterText)
		ApplyDropdownWidth(self.dropdown, GetPopupWidth(self, filteredKeys, filterText))
		self.dropdown:ClearFrames()
		for _, key in ipairs(filteredKeys) do
			local f = GetContentLine()
			local _, size, outline = f.text:GetFont()
			f.text:SetFont(ResolveFont(self, key), size, outline)
			f.text:SetText(key)
			if key == self.value then
				f.check:Show()
			end
			f.obj = self
			self.dropdown:AddFrame(f)
		end
	end

	local function SearchBox_OnTextChanged(this)
		local owner = this.ownerWidget
		if this.placeholder then
			if this:GetText() == "" and not this:HasFocus() then
				this.placeholder:Show()
			else
				this.placeholder:Hide()
			end
		end
		if this.clearButton and this.clearButton.text then
			if this:GetText() == "" then
				this.clearButton.text:SetAlpha(0.45)
			else
				this.clearButton.text:SetAlpha(0.95)
			end
		end
		if owner and owner.dropdown then
			PopulateDropdown(owner, this:GetText())
		end
	end

	local function SearchBox_OnFocusGained(this)
		if this.placeholder then
			this.placeholder:Hide()
		end
	end

	local function SearchBox_OnFocusLost(this)
		if this:GetText() == "" and this.placeholder then
			this.placeholder:Show()
		end
	end

	local function SearchBoxHolder_OnMouseDown(this)
		if this.editBox then
			this.editBox:SetFocus()
		end
	end

	local function SearchClearButton_OnEnter(this)
		if this.text then
			this.text:SetTextColor(SEARCH_CLEAR_HOVER_COLOR[1], SEARCH_CLEAR_HOVER_COLOR[2], SEARCH_CLEAR_HOVER_COLOR[3], SEARCH_CLEAR_HOVER_COLOR[4])
		end
	end

	local function SearchClearButton_OnLeave(this)
		if this.text then
			this.text:SetTextColor(SEARCH_CLEAR_COLOR[1], SEARCH_CLEAR_COLOR[2], SEARCH_CLEAR_COLOR[3], SEARCH_CLEAR_COLOR[4])
		end
	end

	local function SearchClearButton_OnClick(this)
		local searchBox = this.searchBox
		if searchBox then
			searchBox:SetText("")
			searchBox:SetFocus()
		end
	end

	local function EnsureSearchBox(dropdown, widget)
		if not dropdown.searchBox then
			local searchFrame = CreateFrame("Frame", nil, dropdown, BackdropTemplateMixin and "BackdropTemplate")
			searchFrame:SetHeight(20)
			searchFrame:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 18, -16)
			searchFrame:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -SEARCH_RIGHT_PADDING, -16)
			searchFrame:SetBackdrop(SEARCH_BACKDROP)
			searchFrame:SetBackdropColor(SEARCH_BG_COLOR[1], SEARCH_BG_COLOR[2], SEARCH_BG_COLOR[3], SEARCH_BG_COLOR[4])
			searchFrame:SetBackdropBorderColor(SEARCH_BORDER_COLOR[1], SEARCH_BORDER_COLOR[2], SEARCH_BORDER_COLOR[3], SEARCH_BORDER_COLOR[4])
			searchFrame:EnableMouse(true)
			searchFrame:SetScript("OnMouseDown", SearchBoxHolder_OnMouseDown)
			dropdown.searchFrame = searchFrame

			local searchBox = CreateFrame("EditBox", nil, searchFrame)
			searchBox:SetAutoFocus(false)
			searchBox:SetMultiLine(false)
			searchBox:SetPoint("TOPLEFT", searchFrame, "TOPLEFT", 6, -2)
			searchBox:SetPoint("BOTTOMRIGHT", searchFrame, "BOTTOMRIGHT", -20, 2)
			searchBox:SetFontObject(ChatFontNormal)
			searchBox:SetScript("OnTextChanged", SearchBox_OnTextChanged)
			searchBox:SetScript("OnEditFocusGained", SearchBox_OnFocusGained)
			searchBox:SetScript("OnEditFocusLost", SearchBox_OnFocusLost)
			searchBox:SetScript("OnEscapePressed", function(self)
				self:ClearFocus()
			end)
			searchBox:SetTextColor(SEARCH_TEXT_COLOR[1], SEARCH_TEXT_COLOR[2], SEARCH_TEXT_COLOR[3], SEARCH_TEXT_COLOR[4])
			searchBox:SetTextInsets(0, 0, 0, 0)

			local placeholder = searchFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
			placeholder:SetPoint("LEFT", searchFrame, "LEFT", 7, 0)
			placeholder:SetPoint("RIGHT", searchFrame, "RIGHT", -22, 0)
			placeholder:SetJustifyH("LEFT")
			placeholder:SetText(SEARCH_PLACEHOLDER)
			placeholder:SetTextColor(SEARCH_PLACEHOLDER_COLOR[1], SEARCH_PLACEHOLDER_COLOR[2], SEARCH_PLACEHOLDER_COLOR[3], SEARCH_PLACEHOLDER_COLOR[4])
			searchBox.placeholder = placeholder

			local clearButton = CreateFrame("Button", nil, searchFrame)
			clearButton:SetWidth(16)
			clearButton:SetPoint("TOPRIGHT", searchFrame, "TOPRIGHT", -2, -1)
			clearButton:SetPoint("BOTTOMRIGHT", searchFrame, "BOTTOMRIGHT", -2, 1)
			clearButton:SetScript("OnClick", SearchClearButton_OnClick)
			clearButton:SetScript("OnEnter", SearchClearButton_OnEnter)
			clearButton:SetScript("OnLeave", SearchClearButton_OnLeave)

			local clearText = clearButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			clearText:SetPoint("CENTER", clearButton, "CENTER", 0, 0)
			clearText:SetText("X")
			clearText:SetTextColor(SEARCH_CLEAR_COLOR[1], SEARCH_CLEAR_COLOR[2], SEARCH_CLEAR_COLOR[3], SEARCH_CLEAR_COLOR[4])
			clearButton.text = clearText
			clearButton.searchBox = searchBox
			searchBox.clearButton = clearButton

			searchFrame.editBox = searchBox
			dropdown.searchBox = searchBox
		end

		dropdown.searchBox.ownerWidget = widget
		dropdown.searchBox:SetText("")
		dropdown.searchBox:HighlightText()
		dropdown.searchBox:Show()
		dropdown.searchBox:ClearFocus()
		if dropdown.searchBox.placeholder then
			dropdown.searchBox.placeholder:Show()
		end
		if dropdown.searchFrame then
			dropdown.searchFrame:Show()
		end

		dropdown.scrollframe:ClearAllPoints()
		dropdown.scrollframe:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 14, -38)
		dropdown.scrollframe:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -14, 12)
	end

	local function ToggleDrop(this)
		local self = this.obj
		if self.dropdown then
			self.dropdown = AGSMW:ReturnDropDownFrame(self.dropdown)
			AceGUI:ClearFocus()
		else
			AceGUI:SetFocus(self)
			self.dropdown = AGSMW:GetDropDownFrame()
			self.dropdown.ownerFrame = self.frame
			EnsureSearchBox(self.dropdown, self)
			PopulateDropdown(self, "")
			self.dropdown.searchBox:SetFocus()
		end
	end

	local function ClearFocus(self)
		if self.dropdown then
			self.dropdown = AGSMW:ReturnDropDownFrame(self.dropdown)
		end
	end

	local function OnHide(this)
		local self = this.obj
		if self.dropdown then
			self.dropdown = AGSMW:ReturnDropDownFrame(self.dropdown)
		end
	end

	local function Drop_OnEnter(this)
		this.obj:Fire("OnEnter")
	end

	local function Drop_OnLeave(this)
		this.obj:Fire("OnLeave")
	end

	local function Constructor()
		local frame = AGSMW:GetBaseFrame()
		local self = {}

		frame.text:SetJustifyH("LEFT")

		self.type = widgetType
		self.frame = frame
		frame.obj = self
		frame.dropButton.obj = self
		frame.dropButton:SetScript("OnEnter", Drop_OnEnter)
		frame.dropButton:SetScript("OnLeave", Drop_OnLeave)
		frame.dropButton:SetScript("OnClick",ToggleDrop)
		frame:SetScript("OnHide", OnHide)

		self.alignoffset = 31

		self.OnRelease = OnRelease
		self.OnAcquire = OnAcquire
		self.ClearFocus = ClearFocus
		self.SetText = SetText
		self.SetValue = SetValue
		self.GetValue = GetValue
		self.SetList = SetList
		self.SetLabel = SetLabel
		self.SetDisabled = SetDisabled
		self.AddItem = AddItem
		self.SetMultiselect = SetMultiselect
		self.GetMultiselect = GetMultiselect
		self.SetItemValue = SetItemValue
		self.SetItemDisabled = SetItemDisabled
		self.ToggleDrop = ToggleDrop

		AceGUI:RegisterAsWidget(self)
		return self
	end

	AceGUI:RegisterWidgetType(widgetType, Constructor, widgetVersion)

end
