-- vBulletin 4.x Lua parser for Owl
-- Copyright 2013-2016 Adalid Claure
-- http://www.owlclient.com

--- ######################## NOTE!!! ########################
--- ######## This parser is still under development! ########
--- #########################################################

parserName = "vbulletin4x"
parserPrettyName = "vBulletin 4.x"

-- ****** BOARDWARE CONFIGURATION ******
-- These variables are used by Owl to detect which message board
-- softwares are supported by this parser. These variables must 
-- be present in every Owl parser. 
boardware = "vbulletin"
boardwaremin = "4.0"
boardwaremax = "4.9.9.9"

-- Global defaults
PAGENUM  = 1
PERPAGE = 50

-- Implementation
Parser = {}
Parser.__index = Parser

Parser.create = function(url)
	local self = {}

	self.rootForumId = "-1"
	self.baseUrl = url
	self.webclient = webclient.new()
	self.webclient:setUseCookies(true);

	self.name = parserName
	setmetatable(self, Parser)
	return self
end

function Parser:doGetBoardwareInfo()
	local pageSrc, status, isError = self.webclient:get(self.baseUrl, true)
	local doc = sgml.new(pageSrc)
	local tags = doc:getElementsByName("meta", "name", "generator")

	if (#tags > 0) then
		local tag = tags[1]
		local content = tag:attribute("content")
		local version = string.match(content, "([%d%.]+)")
		
		if (version ~= nil) then
			ret = {}
			
			local titleTag = doc:getElementsByName("title", nil, nil)
			if (#titleTag > 0 and #(titleTag[1]:children()) > 0) then
				local title = titleTag[1]:children()[1]:value()
				
				if (title and string.len(title) > 0) then
					title = string.gsub(title, " %- Powered by vBulletin", "", 1)
					if (string.len(title) > 0) then
						ret["name"] = title
					end
				end				
			end
			
			ret["success"] = true
			ret["boardware"] = "vbulletin"
			ret["version"] = version
			
			return ret
		end
	end

	return { ["success"] = false }
end

function Parser:doTestParser(pageSrc)
	return { ["success"] = false }
end

function Parser:doLogin(info)
	local login_data = [[
vb_login_username=%s&cookieuser=1&vb_login_password=
&s=&securitytoken=guest&do=login&vb_login_md5password=%s
&vb_login_md5password_utf=%s
	]]
	
	local username = utils.percentEncode(info.username);
	local md5pw = utils.md5(info.password)
	local postData = string.format(login_data, username, md5pw, md5pw)
	local url = string.format("%s/login.php?do=login", self.baseUrl)

	-- make the login request as a post
	local pageSrc, status, isError = self.webclient:post(url, postData)	
	if (isError == false) then
		local isValid, errorText = self:isValidLogin(pageSrc)
		if (isValid) then
			return { ["success"] = true }
		else
			return { ["success"] = false, ["error"] = errorText }
		end
	else
		return { ["success"] = false, ["error"] = "webclient request failed" }
	end
	
	return { ["success"] = false }
end

-- Accepts the response text from a login request and determines if the
-- login was successful or not
function Parser:isValidLogin(html)
	local loggedin = string.match(html, "var%s+LOGGEDIN%s=%s(%d)")
	local bValid = (loggedin == "1")
	
	if (bValid == false) then
		local doc = sgml.new(html)
		local errorTag = doc:getElementsByName("div", "class", "standard_error")

		if (#errorTag > 0) then
			utils.debug(html)
			local strTemp = string.sub(html, errorTag[1]:startPos(), errorTag[1]:endPos() + errorTag[1]:endLen())
			local tempDoc = sgml.new(strTemp)
			
			errorMsgTag = tempDoc:getElementsByName("div", "class", "blockrow restore")
			errorText = tempDoc:getText(errorMsgTag[1])
			errorText = utils.stripHtml(errorText)
		else
			errorText = "There was an unknown error while logging in. (vbulletin4x#1)"
		end
	end

	return bValid, errorText
end

function Parser:doGetForumList(forumId)
	print("Parser:doGetForumList(forumId)");
	local retList = {}
	local success = false;

	if (forumId == self.rootForumId) then
		retList, success = self:getRootSubForumList()
	else
		retList, success = self:getSubForumList(forumId, 1, 1)
	end

	return retList
end

-- makes the webrequest and parses the resulting HTML.
-- returns an empty list and false if there was a problem
-- TODO: does this function need pageNum?
function Parser:getSubForumList(forumId, pageNum, perPage)
	local retList = {}
	local url = string.format("%s/forumdisplay.php?%s&s=%s",
		self.baseUrl, forumId, self.sessionUrl)

	local pageSrc, status, isError = self.webclient:get(url)
	if (isError == false) then
		retList = self:parseSubForumList(pageSrc)
	else
		return retList, false
	end

	return retList, true
end

-- processes the HTTP result
function Parser:parseSubForumList(html)
	local retlist = {}
	local doc = sgml.new(html);
	
	-- the forums live in a <div id="forumbits"> tree
	local forumBits = doc:getElementsByName("div","id","forumbits");
	
	-- each forum has it's information numbe an element name
	-- something like <li id="forum12">
	-- where '12' is the DB Id of the forum
	local forumIdRx = regexp.new("forum\\d+")

	-- look under <div id="forumbits"> for an <ol> element, 
	-- each forum is an <li> entry in the <ol>'s list
	if (#forumBits > 0 and #forumBits[1]:children() > 0) then
		for i,T in pairs(forumBits[1]:children()) do
			if (T:name():upper() == "OL") then
				for j,C in pairs(T:children()) do
					if (C:hasAttribute("id") and (forumIdRx:indexIn(C:attribute("id")) ~= 1)) then
						
						-- pass the html of this specific <li> element and pass it to the parser
						-- to extract the info
						local THtml = string.sub(html, C:startPos(), C:endPos() + C:endLen() + 1)
						local forumInfo = self:parseSubForumInfo(THtml);
					end
				end				
			end
		end		
	end
	
	return retlist
end

function Parser:parseSubForumInfo(html)
	local doc = sgml.new(html)
	local forumInfo = doc:getElementsByName("div", "class", "foruminfo");
	local forum
	
	utils.debug(html)
	
	if (forumInfo ~= nil and #forumInfo > 0) then
		local infoHtml = string.sub(html, forumInfo[1]:startPos(), forumInfo[1]:endPos() + forumInfo[1]:endLen())
		local infoDoc = sgml.new(infoHtml)
		local imgTag = infoDoc:getElementsByName("img", "class", "forumicon");
		
		if (imgTag ~= nil and #imgTag > 0) then
			
		end
	end
end

-- makes the webrequest for ROOT forum and passed
-- the parsing down to the sub functions
--
-- Return Value: array of tables, entries contains
--		forum['forumId'] (string)
-- 		forum['forumName'] (string)
-- 		forum['forumType'] (int)
--		forum['forumUnread'] (boolean)
--		forum['forumLink'] (string)
function Parser:getRootSubForumList()
	local retList = {}
	local url = string.format("%s/forum.php", self.baseUrl)	
	local pageSrc, status, isError = self.webclient:get(url);

	if (isError == false) then
		retList = self:parseRootForumList(pageSrc)
	else
		return retList, false
	end

	return retList, true
end

function Parser:parseRootForumList(html)
	local retlist = {};
	local iDisplayOrder = 1
	local startTag = "<!%-%-%s+main%s+%-%->"
	local endTag = "<!%-%-%s+/main%s+%-%->"	
	local content = string.match(html, string.format("%s.+%s", startTag, endTag))
	local doc = sgml.new(content)

	utils.debug(content)
		
	local forumRx = regexp.new("forum");
	local catRx = regexp.new("cat");
	
	local olForums = doc:getElementsByName("ol", "id", "forums");
	
	if (#olForums > 0) then
	
		-- go through each child of the <ol id="forums"...> element, and determind if
		-- it is a category or a forum
		for i,T in pairs(olForums[1]:children()) do
			if (T:hasAttribute("id")) then
				local idText = T:attribute("id");
				local forumTable = {}
				local THtml = string.sub(content, T:startPos() + T:startLen() + 1, T:endPos())
				
				if (forumRx:indexIn(idText) ~= -1) then
					forumTable = self:parseRootForum(THtml)
				elseif (catRx:indexIn(idText) ~= -1) then
					forumTable = self:parseRootCategory(THtml)
				end
				
				if (forumTable ~= nil) then
					forumTable["forumDisplayOrder"] = #retlist + 1
					retlist[#retlist + 1] = forumTable;
				end
			end
		end
	end

	return retlist;
end

function Parser:parseRootForum(html)
	local forumId, forumName, forumLink;
	local forumType = ForumType.FORUM
	local forumUnread = false;
	
	local forumTitleRex = regexp.new("forumdisplay\\.php\\?([\\d\\-a-zA-Z]+)")
	local forumNew = regexp.new("forum_new")
	local forumLnk = regexp.new("forum_link")
	
	local liDoc = sgml.new(html)
	local aTag = liDoc:getElementsByName("a", "href", forumTitleRex); 
	
	if (#aTag > 0 and forumTitleRex:indexIn(html) ~= -1) then
		forumId = forumTitleRex:cap(1)
		forumName = string.sub(html,
				aTag[1]:startPos() + aTag[1]:startLen() + 1,
				aTag[1]:endPos())
	end
	
	local imgTag = liDoc:getElementsByName("img", "class", "forumicon");
	if (#imgTag > 0 and imgTag[1]:hasAttribute("src")) then
		if (forumNew:indexIn(imgTag[1]:attribute("src")) ~= -1) then
			forumUnread = true;
		elseif (forumLnk:indexIn(imgTag[1]:attribute("src")) ~= -1) then
			forumType = ForumType.LINK
			forumLink = string.format("%s/forumdisplay.php?f=%s", self.baseUrl, forumId)
		end
	end
	
	return { ["forumId"] = forumId,
			["forumName"] = forumName,
			["forumType"] = forumType,
			["forumUnread"] = forumUnread,
			["forumLink"] = forumLink }	
end

function Parser:parseRootCategory(html)
	local forumId, forumName, forumLink;
	local forumType = ForumType.CATEGORY
	local forumUnread = false;
	
	local forumTitleRex = regexp.new("forumdisplay\\.php\\?([\\d\\-a-zA-Z]+)")
	local liDoc = sgml.new(html)
	local aList = liDoc:getElementsByName("a", "href", forumTitleRex);

	if (#aList > 0 and forumTitleRex:indexIn(html) ~= -1) then
		forumId = forumTitleRex:cap(1)
		forumName = string.sub(html,
				aList[1]:startPos() + aList[1]:startLen() + 1,
				aList[1]:endPos())
	else
		return nil
	end

	return { ["forumId"] = forumId,
			["forumName"] = forumName,
			["forumType"] = forumType,
			["forumUnread"] = forumUnread,
			["forumLink"] = forumLink }	
end
