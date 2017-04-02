-- vBulletin 3.8 Lua parser for Owl
-- Copyright 2013-2016 Adalid Claure
-- http://www.owlclient.com

parserName = "vbulletin3x"
parserPrettyName = "vBulletin 3.x"

-- ****** BOARDWARE CONFIGURATION ******
-- These variables are used by Owl to detect which message board
-- softwares are supported by this parser. These variables must 
-- be present in every Owl parser. 
boardware = "vbulletin"
boardwaremin = "3.6"
boardwaremax = "3.9.9.9"

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

	self.name = parserName
	setmetatable(self, Parser)
	return self
end

function Parser:getForumUrl(forumId)
	local url = ""
	
	if (forumId == self.rootForumId) then
		url = string.format("%s/index.php", self.baseUrl)
	else
		url = string.format("%s/forumdisplay.php?f=%s", self.baseUrl, forumId)
	end

	return url
end

function Parser:getThreadUrl(threadId)
	return string.format("%s/showthread.php?t=%s", self.baseUrl, threadId)	
end

function Parser:getPostUrl(postId)
	return string.format("%s/showpost.php?p=%s", self.baseUrl, postId)
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
	local doc = sgml.new(pageSrc)
	if (doc ~= nil) then
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
	end

	return { ["success"] = false }
end

function Parser:doGetEncryptionSettings()
	local ret = {}
	local url = string.format("%s/misc.php?do=getowlkey", self.baseUrl)
	local pageSrc, status, isError = self.webclient:getRaw(url)
	
	ret["success"] = false
	
	if (isError == false) then
		local doc = sgml.new(pageSrc)

		local keyList = doc:getElementsByName("key", nil, nil)
		local seedList = doc:getElementsByName("seed", nil, nil)
		
		if (#keyList > 0 and #seedList > 0) then
			ret["key"] = doc:getText(keyList[1])
			ret["seed"] = doc:getText(seedList[1])
			ret["success"] = true
		end
	end
	
	return ret
end

function Parser:doLogin(info)
	local login_data = [[
vb_login_username=%s&cookieuser=1&vb_login_password=
&s=&securitytoken=guest&do=login&vb_login_md5password=%s
&vb_login_md5password_utf=%s
	]]

	self.sessionUrl = "";
	self.securityToken = "";
	
	local username = utils.percentEncode(info.username);
	local md5pw = utils.md5(info.password)
	local postData = string.format(login_data, username, md5pw, md5pw)
	local url = string.format("%s/login.php?do=login", self.baseUrl)

	-- make the login request as a post
	local pageSrc, status, isError = self.webclient:post(url, postData)	
	
	if (isError) then
		return { ["success"] = false, ["error"] = "webclient request failed" }
	else
		local isValid, errorText = self:isValidLogin(pageSrc)
		if (isValid) then
			-- securityToken is only set for vb3.7 and above
			if (self.securityToken ~= nil) then
				return 
				{ 	
					["success"] = true,
					["sessionKey"] = self.sessionUrl,
					["securityToken"] = self.securityToken 
				}
			else
				return 
				{ 
					["success"] = true, 
					["sessionKey"] = self.sessionUrl 
				}
			end
		else
			return { ["success"] = false, ["error"] = errorText }
		end
	end

	return { ["success"] = false }
end

-- Accepts the response text from a login request and determines if the
-- login was successful or not
function Parser:isValidLogin(html)
	local bValid = false;
	local errorText = string.match(html, "<!%-%- main error message %-%->(.-)<!%-%- / main error message %-%->")

	if (errorText == nil) then
		local root = string.match(html, "window%.location%s*=%s*\"(.-)\"")
		local pageSrc, status, isError = self.webclient:get(root)
		
		if (isError == false) then
			local secToken = string.match(pageSrc,"var%s+SECURITYTOKEN%s*=%s*\"([%a%d%-]+)\"")
			if (secToken ~= nil and secToken ~= "guest") then
				bValid = true
			else
				errorText = "The message board returned an invalid security token."
			end
		end
	else
		-- strip the html from the error text and trim the string
		errorText = string.gsub(errorText,"<.->", "")
		errorText = string.gsub(errorText,"^%s*(.-)%s*$", "%1")
		errorText = string.gsub(errorText,"%s+"," ")
	end

	return bValid, errorText
end

function Parser:doGetForumList(forumId)
	local retList = {}
	local success = false;

	if (forumId == self.rootForumId) then
		retList, success = self:getRootSubForumList()
	else
		retList, success = self:getSubForumList(forumId, 1, 1)
	end

	return retList
end

-- makes the webrequest and passes the resulting HTML.
-- returns an empty list and false if there was a problem
-- TODO: does this function need pageNum?
function Parser:getSubForumList(forumId, pageNum, perPage)
	local retList = {}
	local url = string.format("%s/forumdisplay.php?f=%s&page=%s&pp=%s&order=desc",
		self.baseUrl, forumId, pageNum, perPage)
	
	local pageSrc, status, isError = self.webclient:get(url)
	if (isError == false) then
		retList = self:parseSubForumList(pageSrc)
	else
		return retList, false
	end

	return retList, true
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
	local foundForums = false

	-- Try the forum.php first with no parameter
	local url = string.format("%s/forum.php", self.baseUrl)
	local pageSrc, status, isError = self.webclient:get(url)
	
	if (isError == false) then
		retList = self:parseRootForumList(pageSrc)
		foundForums = retList ~= nil and #retList > 0
	end
	
	-- Next try the index.php 
	if (foundForums == false) then
		local url = string.format("%s/index.php", self.baseUrl, self.sessionUrl)
		local pageSrc, status, isError = self.webclient:get(url)
		
		retList = self:parseRootForumList(pageSrc)
		foundForums = retList ~= nil and #retList > 0
	end
	
	-- Lastly try the forumId of -1
	if (foundForums == false) then
		local url = string.format("%s/forumdisplay.php?f=%s&page=1&pp=1&order=desc", self.baseUrl, self.rootForumId)			
		local pageSrc, status, isError = self.webclient:get(url)		
		
		if (isError == false) then
			retList = self:parseRootForumList(pageSrc)			
		end
	end

	-- return Success, opposite of isError
	return retList, true
end

-- For a !ROOT forum, parse the data between the comment tags
-- <!-- sub-forum list --> .... <!-- /sub-forum list -->
-- RETURNS: array of forum tables
function Parser:parseSubForumList(html)
	local retlist = {};
	local startTag = "<!%-%-%s+sub%-forum%s+list%s+%-%->"
	local endTag = "<!%-%-%s+/%s+sub%-forum%s+list%s+%-%->"

	local content = string.match(html, string.format("%s.+%s", startTag, endTag))
	local doc = sgml.new(content)
	local subForumTable = nil

	-- assume that the subforums are in the second table after the
	-- <!-- sub-forum list --> comment
	local iCount = 0;
	local children = doc:doctag():children()
	for i,T in pairs(children) do
		if (children[i]:name():upper() == "TABLE") then
			if (iCount >= 1) then
				subForumTable = children[i]
				break
			end
			iCount = iCount +1
		end
	end

	if (subForumTable == nil) then
		return retlist
	end

	-- iterate through the subForumTable
	local iDisplayOrder = 1;
	local colRx = regexp.new("collapseobj_forumbit_\\d+")
	local subChildren = subForumTable:children();

	-- go through each child in the subForumTable and parse it if it looks
	-- like something important
	for x,Y in pairs(subChildren) do
		if (Y:name():upper() == "TBODY") then
			if ((Y:hasAttribute("id") == false or colRx:indexIn(Y:attribute("id")) == -1)
				and Y:endPos() > Y:startPos()) then

				local body = string.sub(content,Y:startPos(),Y:endPos() + Y:endLen() + 1)

				-- return nil if the forum is a child forum or if it was unable to parse,
				-- a parsing error is generated inside parseSubForumTBody
				local newForum = self:parseSubForumTBody(body);
				if (newForum ~= nil) then
					newForum["forumDisplayOrder"] = iDisplayOrder;
					retlist[#retlist + 1] = newForum;
					iDisplayOrder = iDisplayOrder + 1;
				else
					-- TODO: error?
				end
			end
		end
	end

	if (#retlist == 0) then
		-- TODO: log error
		-- utils.debug("no sub forums found");
		--debug.debug()
	end

	return retlist;
end

function Parser:parseSubForumTBody(body)
	-- the forum info we're scrapping
	local forumName, forumType, forumId, forumLink
	local forumUnread = false
	
	local forumDisplayRx = regexp.new("forumdisplay\\.php\\?[^>]*f=(\\d+)")
	local fId = regexp.new("f\\d+")
	local imgId = regexp.new("forum_statusicon_\\d+");
	local newSearch = regexp.new("_new\\.gif|png|jpg|jpeg|bmp")
	local linkSearch = regexp.new("_link\\.gif|png|jpg|jpeg|bmp")
	local tbodyDoc = sgml.new(body)
	local tempList = tbodyDoc:getElementsByName("a","href",forumDisplayRx)
	
	-- the <tbody> element with no <a> element is probably the element that says
	-- something like: Sub-Forums: General Topics
	if (#tempList > 0) then
		local ahref = nil;

		-- the regex will return <a> elements with <img> elements as the body
		-- so we loop through all the <a> elements looking for the first one
		-- with text and assume that is the forum name
		for x,I in pairs(tempList) do
			ahref = I;
			-- get the outer html
			local linkTemp = string.sub(body,ahref:startPos() + 1, ahref:endPos() + ahref:endLen())

			if (strName == nil and forumDisplayRx:indexIn(linkTemp) ~= -1) then
				forumId = forumDisplayRx:cap(1);
			end

			if (strName == nil) then
				forumName = tbodyDoc:getText(ahref);
			end

			if (forumName ~= nil and forumId ~= nil) then
				break
			end
		end

		if (forumName == nil or forumId == nil) then
			return nil
		end

		-- look for a <td ... id="fXX"> element,
		-- if exists then this is a Forum::FORUM
		-- if !exists then this is a  Forum::CATEGORY
		local templist = tbodyDoc:getElementsByName("td", "id", fId)
		if (#templist > 0) then
			-- if <td .. id="fXX"> exists, then this is a FORUM
			-- (VBulletin.cpp:~772)
			local aTd = templist[1]
			local prev = aTd:previous()

			-- if the previous node is a <td> element then assume
			-- this forum is a child sub forum, otherwise we assume
			-- it's at the same level and should be returned
			if (prev ~= nil and prev:name():upper() == "TD") then
				return nil
			end

			local templist2 = tbodyDoc:getElementsByName("img", "src", linkSearch)
			if (#templist2 > 0) then
				forumType = ForumType.LINK
				forumLink = string.format("%s/forumdisplay.php?f=%s", self.baseUrl, forumId)
			else
				forumType = ForumType.FORUM
				-- check to see if this forum has any unread posts
				local templist3 = tbodyDoc:getElementsByName("img", "id", imgId)
				if (#templist3 > 0) then
					local imgtag = templist3[1]
					if (imgtag:hasAttribute("src") ~= nil and newSearch:indexIn(imgtag:attribute("src")) ~= 1) then
						forumUnread = true;
					end
				end
			end
		else
			-- else <td .. id="fXX"> doesn't exist, then this is a CATEGORY
			-- (VBulletin.cpp:~830)
			if (ahref ~= nil) then
				-- if the <a> element is in the first <td> of the <tbody> then
				-- we can assume this category is of the root, otherwise we
				-- assume it's a sub category and dismiss it
				if (ahref:parent() ~= nil
					and ahref:parent():parent() ~= nil
					and ahref:parent():parent():children()[1] ~= nil
					and ahref:parent():compare(ahref:parent():parent():children()[1]) == false)
				then
					return nil;
				end

				local templist2 = tbodyDoc:getElementsByName("img", "src", fId)
				if (#templist2 > 0) then
					forumType = ForumType.LINK
					forumLink = string.format("%s/forumdisplay.php?f=%s", self.baseUrl, forumId)
				else
					forumType = ForumType.CATEGORY
				end
			else
				-- TODO: throw error
			end
		end
	else
		-- TODO: throw an error
	end

	return { ["forumId"] = forumId,
			["forumName"] = utils.stripHtml(forumName),
			["forumType"] = forumType,
			["forumUnread"] = forumUnread,
			["forumLink"] = forumLink }
end

-- for the ROOT forum extract and parse the HTML between the two tags
-- <!-- main --> ....<!-- /main -->
function Parser:parseRootForumList(html)
	local startTag = "<!%-%-%s+main%s+%-%->"
	local endTag = "<!%-%-%s+/%s*main%s+%-%->"
	local colObjRx = regexp.new("collapseobj_forumbit_\\d+")

	local content = string.match(html, string.format("%s.+%s", startTag, endTag))
	local doc = sgml.new(content)
	local tables = doc:getElementsByName("table", nil, nil)
	local retList = {}
	local iDisplayOrder = 1
	
	if (#tables > 0) then
		local children = tables[1]:children()

		-- go through all the <tbody> elements between the <!-- main --> and <!-- /main -->
		-- comments if the <tbody> element has an id="collapseobj_forumbit_XX" atribute
		-- then the forum is contained in a category, so skip it.
		-- otherwise we have to do some work to determine if the forum is a category of a
		-- forum
		for i,T in pairs(children) do
			local tag = children[i]
			if (tag:name():upper() == "TBODY") then
				if (not tag:hasAttribute("id") or colObjRx:indexIn(tag:attribute("id")) == -1) then
					local body = string.sub(content,tag:startPos(),tag:endPos() + tag:endLen() + 1)
					local parsed = self:parserRootTBody(body)
					if (parsed ~= nil) then
						local newForum = parsed; --self:parserRootTBody(body)
						newForum["forumDisplayOrder"] = iDisplayOrder						
						retList[#retList + 1] = newForum
						iDisplayOrder = iDisplayOrder + 1
					end
				end
			end
		end
	end

	return retList
end

-- for the ROOT forum extract and parser the data in each tbody
-- <tbody>....</tbody>
function Parser:parserRootTBody(body)
	-- the forum info we're scrapping
	local forumName, forumType, forumId, forumLink
	local forumUnread = false

	-- declare some of our regexs ahead of time
	local forumDisplayRx = regexp.new("forumdisplay\\.php\\?[^>]*f=(\\d+)")
	local fId = regexp.new("f\\d+")
	local linkSearch = regexp.new("forum_link\\.gif|png|jpg|jpeg|bmp")
	local imgId = regexp.new("forum_statusicon_\\d+")
	local newSearch = regexp.new("_new\\.gif|png|jpg|jpeg|bmp")

	local bodyDoc = sgml.new(body)
	local fdtags = bodyDoc:getElementsByName("a","href",forumDisplayRx)

	-- make sure we have a link to a forum, this link should look something
	-- like <a href="forumdisplay.php?f=XX">
	if (#fdtags > 0 and forumDisplayRx:indexIn(fdtags[1]:attribute("href")) ~= -1) then
		forumType = -1
		forumId = forumDisplayRx:cap(1)
		forumName = string.sub(body,
				fdtags[1]:startPos() + fdtags[1]:startLen() + 1,
				fdtags[1]:endPos())
		forumName = utils.stripHtml(forumName)

		-- look for a <td ... id="fXX"> element, if it doesn't exist
		-- then we assume the forum is a Forum::CATEGORY or Forum::LINK
		local idTags = bodyDoc:getElementsByName("td", "id", fId)
		if (#idTags > 0) then
			-- if the previous sibling is a <td> element then we assume
			-- this forum is a child sub forum, otherwise we assume it
			-- is a root forum
			local aTd = idTags[1]
			local prev = aTd:previous()

			if (prev ~= nil and prev:name():upper() == "td") then
				return
			end

			local tempList = bodyDoc:getElementsByName("img","src",linkSearch)
			if (#tempList > 0) then
				forumType = ForumType.LINK

				-- with vb3.x, the link is showed as a forumdisplay link and
				-- vbulletin redirects on the server end
				forumLink = string.format("%s/forumdisplay.php?f=%s", self.baseUrl, forumId)
			else
				-- this is a forum
				forumType = ForumType.FORUM

				-- check to see if this has unread posts
				tempList = {}
				tempList = bodyDoc:getElementsByName("img", "id", imgId)
				if (#tempList > 0) then
					local imgTag = tempList[1];
					if (imgTag:hasAttribute("src") and newSearch:indexIn(imgTag:attribute("src"))) then
						forumUnread = true
					end
				else
					-- error?
				end
			end
		else
			local tmpList = bodyDoc:getElementsByName("img","src",linkSearch)
			if (#tmpList > 0) then
				forumType = ForumType.LINK
			else
				forumType = ForumType.CATEGORY
			end
		end
	end

	if (forumId == nil) then
		return nil
	end

	return { ["forumId"] = forumId,
			["forumName"] = utils.stripHtml(forumName),
			["forumType"] = forumType,
			["forumUnread"] = forumUnread,
			["forumLink"] = forumLink }
end

function Parser:doThreadList(forumId, pageNum, perPage, bForceReload)
	local retList = {}
	local forumInfo = {}
	
	local url = string.format("%s/forumdisplay.php?f=%s&page=%s&pp=%s&order=desc",
		self.baseUrl, forumId, pageNum, perPage)

	local pageSrc, status, isError = self.webclient:get(url, bForceReload)

	if (isError == false) then
		retList = self:parseThreadList(pageSrc)
		
		forumInfo["threadId"] = forumId
		forumInfo["pageNum"] = pageNum
		forumInfo["perPage"] = perPage
		
		local pageCount = string.match(pageSrc,">%s*Page%s+%d+%s+of%s+(%d+)%s*<")
		if (not pageCount) then
			forumInfo["pageCount"] = 1
		else
			forumInfo["pageCount"] = pageCount			
		end

		retList["#forumInfo"] = forumInfo			
	else
		-- TODO: log generic error?
	end

	return retList;
end

function Parser:parseThreadList(html)
	local retlist = {}

	local bodyDoc = sgml.new(html);
	local tbfRegEx = regexp.new("threadbits_forum_[\\d]+");
	local tmpList = bodyDoc:getElementsByName("tbody","id",tbfRegEx)

	if (#tmpList == 0) then
		-- No <tbody> element probably means that the forum being
		-- searched is a CATEGORY or it has no threads
		return retlist;
	end

	-- extract the <tbody>...</tbdoy> HTML
	-- (VBulletin3.cpp:1271)
	local tbodyTag = tmpList[1];
	local tbody = string.sub(html, tbodyTag:startPos(), tbodyTag:endPos() + tbodyTag:endLen());
	local tbodyDoc = sgml.new(tbody);
	local trTags = tbodyDoc:getElementsByName("tr", nil, nil)
	for i,T in pairs(trTags) do
		local trContent = string.sub(tbody, T:startPos(), T:endPos() + T:endLen())
		local threadInfo = self:getThreadInfo(trContent)

		if (threadInfo ~= nil) then
			retlist[#retlist + 1] = threadInfo
		end
	end

	return retlist;
end

function Parser:getThreadInfo(trContent)
	local retinfo = {}
	local strId = nil
	local strTitle = nil
	local strPreview, strAuthor
	local lpAuthor, lpId, lpTime, lpDate
	local bSticky = false
	local bHasUnread = false

	local regexSI = regexp.new("thread_*statusicon_([\\d]*)");
	local titleRex = regexp.new("thread[_]*title_([\\d]*)");

	local trDoc = sgml.new(trContent)

	-- VBulletin.cpp:1332
	for i,T in pairs(trDoc:getElementsByName("td", nil, nil)) do
		local strTemp = string.sub(trContent, T:startPos(), T:endPos() + T:endLen())

		if (T:hasAttribute("id")) then
			local strTagId = T:attribute("id");

			if (regexSI:indexIn(strTagId) ~= -1) then
			-- we hit something like: <td class="alt1" id="td_threadstatusicon_21612">
			-- which is usually the first one we hit, from this element and its
			-- children we can get the threadId and the hasUnread-boolean

				strId = regexSI:cap(1);
				local tempDoc = sgml.new(strTemp)
				local tempTags = tempDoc:getElementsByName("img","id",regexSI)
				if (#tempTags > 0) then
					local firstTag = tempTags[1]
					if (firstTag:hasAttribute("src")) then
						local src = firstTag:attribute("src");
						local moved = regexp.new("_moved.*\\.[gif|png|jpg|jpeg|bmp]+");
						if (moved:indexIn(src) ~= -1) then
							-- moved thread; bail out
							return nil;
						else
							local newSearch = regexp.new("_new\\.[gif|png|jpg|jpeg|bmp]")
							if (newSearch:indexIn(src) ~= -1) then
								bHasUnread = true
							end
						end
					end
				end
			elseif (titleRex:indexIn(strTagId) ~= -1) then
			-- something like: <td class="alt1" id="td_threadtitle_81054" title="thread text preview">
			-- from which we can extract the thread title and preview text
			-- (VBulletin.cpp:1385)
				if (T:hasAttribute("title")) then
					strPreview = T:attribute("title")
				end

				local tempDoc = sgml.new(strTemp)
				local tempTags = tempDoc:getElementsByName("a","id", titleRex)
				if (#tempTags > 0) then
					local firstTag = tempTags[1]
					strTitle = string.sub(strTemp, firstTag:startPos() + firstTag:startLen() + 1, firstTag:endPos())
					strTitle = utils.stripHtml(strTitle)
				end

				-- determine if the thread is stickied
				local stickyRex = regexp.new("sticky\\.[gif|png|jpg|jpeg|bmp]")
				tempTags = tempDoc:getElementsByName("img","src",stickyRex)
				bSticky = #tempTags > 0

				local memberRex = regexp.new("window.open\\([^>]*\\)")
				tempTags = tempDoc:getElementsByName("span","onclick",memberRex)
				if (#tempTags > 0) then
					local firstTag = tempTags[1]
					strAuthor = string.sub(strTemp, firstTag:startPos() + firstTag:startLen() + 1, firstTag:endPos())
					strAuthor = utils.stripHtml(strAuthor)
				end
			end
		else
			-- get information about the last post
			-- VBulletin3.cpp:1421
			local lastPostRex = regexp.new("lastpost\\.gif|png|jpg|jpeg|bmp")
			if (lastPostRex:indexIn(strTemp) ~= -1) then
			
				local tempRex = regexp.new("find=lastposter")
				local tempDoc = sgml.new(strTemp)
				local tempTags = tempDoc:getElementsByName("a","href",tempRex)
				if (#tempTags > 0) then
				    local firstTag = tempTags[1]
				    lpAuthor = string.sub(strTemp, firstTag:startPos() + firstTag:startLen() + 1, firstTag:endPos())
				    lpAuthor = utils.stripHtml(lpAuthor)
				else
					-- TODO: warning that lastPostAuthor could not be found
				end
				
				local tempRex2 = regexp.new("showthread\\.php\\?[^>]*p=([\\d]+)#post[\\d]+")
				if (tempRex2:indexIn(strTemp) ~= -1) then
					lpId = tempRex2:cap(1)
				else
					-- TODO: warning that lastPostId could not be found
				end
				
				-- extract the last post date & time
				tempTags = tempDoc:getElementsByName("span", "class", "time")
				if (#tempTags > 0) then
				    local firstTag = tempTags[1]
				    lpTime = string.sub(strTemp, firstTag:startPos() + firstTag:startLen() + 1, firstTag:endPos())
				    lpTime = utils.stripHtml(lpTime)

					local firstTagParent = firstTag:parent()
					local iStart = firstTagParent:startPos() + firstTagParent:startLen() + 1
					local iEnd = firstTag:startPos()
					
					lpDate = string.sub(strTemp, iStart, iEnd)
				else
					-- TODO: warning that lastPostDate and lastPostTime could not be found (VBulletin.cpp:1461)
				end
			end
		end
	end

	if (strId == nil or strTitle == nill and strAuthor == nil) then
		return nil
	end

	return
	{
		["threadId"] = strId,
		["threadTitle"] = utils.stripHtml(strTitle),
		["threadAuthor"] = strAuthor,
		["threadHasUnread"] = bHasUnread,
		["threadIsSticky"] = bSticky,
		["threadPreviewText"] = strPreview,
		["threadLastPostId"] = lpId,
		["threadLastPostAuthor"] = lpAuthor,
		["threadLastPostTime"] = lpTime,
		["threadLastPostDate"] = lpDate
	}
end

function Parser:doGetUnreadForums()
	local retlist = {}
	local idlist = {} -- index used to avoid duplicates
	
	local url = string.format("%s/search.php?do=getnew",self.baseUrl)
	local pageSrc, status, isError = self.webclient:get(url, true)
	
	local doc = sgml.new(pageSrc)
	local listTable = doc:getElementsByName("table", "id", "threadslist")
	if (#listTable > 0 and #(listTable[1]:children()) > 0) then
		local tags = listTable[1]:children()
		for i,T in pairs(tags) do
			local tagHtml = string.sub(pageSrc, T:startPos(), T:endPos() + T:endLen())
			local forumInfo = self:getUnreadForumInfo(tagHtml);

			if (forumInfo ~= nil) then
				local id = forumInfo["forumId"]
				
				if (id ~= nil and idlist[id] == nil) then
					idlist[id] = 1;
					retlist[#retlist + 1] = forumInfo
				end
			end
		end	
	end

	return retlist
end

function Parser:getUnreadForumInfo(html)
	local info = {}
	local forumDisplayRx = regexp.new("forumdisplay\\.php\\?[^>]*f=(\\d+)")

	local tbodyDoc = sgml.new(html)
	local tempList = tbodyDoc:getElementsByName("a","href",forumDisplayRx)
	if (#tempList > 0) then
		info["forumId"] = forumDisplayRx:cap(1);
		
		local alink = tempList[1]
		info["forumName"] = utils.stripHtml(string.sub(html, alink:startPos() + alink:startLen() + 1, alink:endPos()))
		info["forumType"] = ForumType.FORUM
		info["forumUnread"] = true;
	else
		return nil
	end

	return info
end

-- returns two tables
-- first table is a list of posts
-- second table is threadInfo, this is a copy of the info passed along
--		with threadInfo["totalPages"] which is parsed from the request
function Parser:doPostList(threadId, pageNum, perPage, bForceReload)
	local retList = {}
	local threadInfo = {} 
	
	local url = string.format("%s/showthread.php?t=%s&page=%s&pp=%s&order=desc",
		self.baseUrl, threadId, pageNum, perPage)

	local pageSrc, status, isError = self.webclient:get(url, bForceReload)

	if (isError == false) then
		-- get the post list
		retList = self:parsePostList(pageSrc)

		-- set the threadId
		threadInfo["threadId"] = threadId
		
		local doc = sgml.new(pageSrc)
		
		-- set the per page
		local perpageEl = doc:getElementsByName("input", "name", "pp")
		if (#perpageEl > 0) then
			local input = perpageEl[1]
			if (input:hasAttribute("value")) then
				local foo = input:attribute("value")
				threadInfo["perPage"] = input:attribute("value")
			else
				-- the default per page value is 25
				threadInfo["perPage"] = "25"
			end
		end				
		
		-- set the current page number
		local pageNumEl = doc:getElementsByName("input", "name", "page")
		if (#pageNumEl > 0) then
			local input = pageNumEl[1]
			if (input:hasAttribute("value")) then
				threadInfo["pageNum"] = input:attribute("value")
			else
				-- the default page number is 1
				threadInfo["pageNum"] = "1"
			end
		end			
		
		-- set the page count
		local pageCount = string.match(pageSrc,">%s*Page%s+%d+%s+of%s+(%d+)%s*<")
		if (not pageCount) then
			threadInfo["pageCount"] = 1
		else
			threadInfo["pageCount"] = pageCount			
		end

		retList["#threadInfo"] = threadInfo		
	end

	return retList
end

-- TODO: Owl 1.0+ figure out why calls to this are not parsing the postList correctly!
function Parser:doUnreadPostList(threadId, bForceReload)
	local retList = {}
	local threadInfo = {} 
	
	local url = string.format("%s/showthread.php?goto=newpost&t=%s",self.baseUrl, threadId)
	local pageSrc, status, isError = self.webclient:get(url, bForceReload)

	if (isError == false) then
		-- get the post list
		retList = self:parsePostList(pageSrc)
	
		-- set the threadID
		threadInfo["threadId"] = threadId
		
		local doc = sgml.new(pageSrc)

		-- set the per page
		local perpageEl = doc:getElementsByName("input", "name", "pp")
		if (#perpageEl > 0) then
			local input = perpageEl[1]
			if (input:hasAttribute("value")) then
				threadInfo["perPage"] = input:attribute("value")
			else
				-- the default per page value is 25
				threadInfo["perPage"] = "25"
			end
		end				
		
		-- set the current page number
		local pageNumEl = doc:getElementsByName("input", "name", "page")
		if (#pageNumEl > 0) then
			local input = pageNumEl[1]
			if (input:hasAttribute("value")) then
				threadInfo["pageNum"] = input:attribute("value")
			else
				-- the default page number is 1
				threadInfo["pageNum"] = "1"
			end
		end			
		
		-- set the page count
		local pageCount = string.match(pageSrc,">%s*Page%s+%d+%s+of%s+(%d+)%s*<")
		if (not pageCount) then
			threadInfo["pageCount"] = 1
		else
			threadInfo["pageCount"] = pageCount			
		end
		
		-- set the ID of the first unread post
		local firstUnreadId = string.match(self.webclient:getLastUrl(), "%#post(%d+)")		
		threadInfo["firstUnreadId"] = firstUnreadId			
		
		retList["#threadInfo"] = threadInfo		
	end

	return retList
end

function Parser:parsePostList(html)
	local retlist = {}
	local postCap = "(<!%-%-%s+post%s+#%d+%s+%-%->.-<!%-%-%s+/%s+post%s+#%d+%s+%-%->)"
	local postBody = string.match(html, postCap)
	
	for postBody in string.gmatch(html, postCap) do
		local P = self:getPostInfo(postBody)
		if (P ~= nil) then
			retlist[#retlist + 1] = P
		end
	end

	return retlist
end

--- Parses HTML looking for information about a post.
-- This function accepts the surrounding HTML of a post and is invoked
-- by Parser:parsePostList. If the function cannot extract the fields
-- marked as 'required' then the function returns nil.
-- @return A table
-- @field postInfo["post.id"] The Id of the post
-- @field postInfo["post.userid"] The Id of the user who wrote the post
-- @field postInfo["post.username"] The username of the post's author (required)
-- @field postInfo["post.text"] Raw HTML text of the post (required)
-- @field postInfo["post.timestamp"] Raw text of the post's timestamp
function Parser:getPostInfo(postHtml)
	local postInfo = {}
	
	local postId = string.match(postHtml, "<!%-%-%s+post%s+#(%d+)%s+%-%->")
	if (postId ~= nil) then
		postInfo["post.id"] = postId
	else
		postInfo["post.id"] = -1
		error.warn({ 
			["error-text"] = "Cannot extract 'post.id'", 
			["html"] = postHtml,
			["url"] = self.webclient:getLastUrl() 
		})		
	end
	
	-- get the username
	local tempDoc = sgml.new(postHtml)
	local tags = tempDoc:getElementsByName("a","class","bigusername")
	if (#tags > 0) then
		local anchor = tags[1]
		
		if (anchor:hasAttribute("href")) then
			local authorId = string.match(anchor:attribute("href"), "member.php%?.*u=(%d+)")
			if (authorId ~= nil) then
				postInfo["postAuthorId"] = authorId
			else
				postInfo["post.userid"] = -1			
				error.warn({ 
					["error-text"] = "Cannot extract 'post.userid'", 
					["html"] = postHtml,
					["url"] = self.webclient:getLastUrl() 
				})						
			end
		else
			postInfo["post.userid"] = -1
			error.warn({ 
				["error-text"] = "Cannot extract 'post.userid'", 
				["html"] = postHtml,
				["url"] = self.webclient:getLastUrl() 
			})		
		end
		
		local author = string.sub(postHtml, anchor:startPos()+1, anchor:endPos() + anchor:endLen())
		local aStripped = utils.stripHtml(author)
		
		if (string.len(aStripped) > 0) then
			postInfo["post.username"] = aStripped
		elseif (string.len(author) > 0) then
			postInfo["post.username"] = author
		else
			postInfo["post.username"] = "#<Unknown Username>"
			error.warn({ 
				["error-text"] = "Cannot extract 'post.username'", 
				["html"] = postHtml,
				["url"] = self.webclient:getLastUrl() 
			})			
		end		
	else
		-- test to see if this person is on the user's ignore list
		local ignoreTest = regexp.new("profile.php?[^>]*do=removelist")
		tags = tempDoc:getElementsByName("a", "href", ignoreTest)
		
		if (#tags == 0) then
			postInfo["post.username"] = "#<Unknown Username>"
			error.warn({ 
				["error-text"] = "Could not extract 'post.username'", 
				["html"] = postHtml,
				["url"] = self.webclient:getLastUrl() 
			})			
		else
			-- author of this post is being ignored by the user to skip
			-- this post entirely
			return nil
		end	
	end
	
	postInfo["post.text"] = self:extractMessageText(postHtml)
	if (postInfo["post.text"] == nil or string.len(postInfo["post.text"]) == 0) then
		error.warn({ 
			["error-text"] = "Could not extract 'post.text', skipping post", 
			["html"] = postHtml,
			["url"] = self.webclient:getLastUrl() 
		})			
		return nil
	end
	
	-- extract the date & time
	local aname = regexp.new("post\\d+")
	local tags = tempDoc:getElementsByName("a", "name", aname)
	
	if (#tags > 0 and tags[1]:parent() ~= nil) then 
		local parent = tags[1]:parent()
		local dateText = string.sub(postHtml, parent:startPos(), parent:endPos() + parent:endLen())
		
		-- utils.strip puts a ? into the string when there are comments
		-- in the HTML, so strip it out here
		dateText = string.gsub(utils.stripHtml(dateText), "%?", "")
		dateText = dateText:gsub("^%s*(.-)%s*$", "%1")
		postInfo["post.timestamp"] = dateText

		if (string.match(dateText,",")) then
			local datestr, timestr = dateText:match("([^,]+),([^,]+)")
			postInfo["post.date"] = datestr
			postInfo["post.time"] = timestr
		end
	else
		postInfo["post.timestamp"] = "#<Unknown Date/Time>"
		error.warn({ 
			["error-text"] = "Could not extract 'post.timestamp'", 
			["html"] = postHtml,
			["url"] = self.webclient:getLastUrl() 
		})			
	end	
	
	return postInfo
end

function Parser:extractMessageText(html)
	local text = nil
	local tempDoc = sgml.new(html)
	local postMsg = regexp.new("post_message_\\d+")
	local tags = tempDoc:getElementsByName("div","id", postMsg)
	
	if (#tags > 0) then
		local msgTag = tags[1]
		text = string.sub(html, msgTag:startPos(), msgTag:endPos()  + msgTag:endLen() + 1)
	else
		text = string.match(html, "<!%-%-%s+message%s+%-%->(.-)<!%-%-%s+/%s*message%s+%-%->")
	end

	if (text ~= nil and #text > 0) then
		text = self:htmlToBBCode(text)
	end
		
	return text
end

function escape(s)
  s = string.gsub(s, "[^ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~]", 
			function (c)
				return string.format ("%%%02X", string.byte(c))
			end)
			
  return s
end
 
function decode(s)
  s = string.gsub (s, "%%([0-9a-fA-F][1-9a-fA-F])", function (n)
                return string.char (tonumber ("0x" .. n));
                end)
  return s;
end;

-- postInfo["parentId"] (string) - the threadId destination
-- postInfo["postTitle"] (string)
-- postInfo["postText"] (string)
function Parser:doSubmitNewPost(postInfo)
	local prePostUrl = string.format("%s/newreply.php?do=newreply&noquote=1&t=%s",
		self.baseUrl, postInfo["parentId"])

	local postParams = {}
	
	do
		local pageSrc, status, isError = self.webclient:get(prePostUrl, true)	
		local preDoc = sgml.new(pageSrc)
		local formTags = preDoc:getElementsByName("form","name","vbform")
		
		if (#formTags == 1) then
			local hiddenTags = preDoc:getElementsByName("input","type","hidden")
			for i,T in pairs(hiddenTags) do
				if (T:hasAttribute("name") and T:hasAttribute("value")) then
					local name = T:attribute("name")
					local value = T:attribute("value")
					postParams[name] = value
				end
			end
		else
			-- vbulletin will give back an error page that we can parser and report
			-- back to the user
			local errorText = self:getErrorText(pageSrc)
			error.throw({ 
				["error-text"] = errorText, 
				["html"] = pageSrc,
				["url"] = prePostUrl,				
			})
			return nil
		end
	end

	-- prepare the subject
	postParams["subject"] = escape(postInfo["postTitle"])
	postParams["subject"] = string.gsub(postParams["subject"], "%%20", "+")	
	
	-- prepare the message
	postParams["message"] = escape(postInfo["postText"])
	postParams["message"] = string.gsub(postParams["message"], "%%20", "+")	

	postParams["taglist"] = postInfo["postTags"]
	postParams["signature"] = 1 -- 0 disables signature
	postParams["parseurl"] = 1
	
	local postUrl = string.format("%s/newreply.php?do=postreply&t=%s",
		self.baseUrl, postInfo["parentId"])	
		
	local payload = nil
	for k,V in pairs(postParams) do
		if (not payload) then
			payload = string.format("%s=%s", k, V)
		else
			payload = string.format("%s&%s=%s", payload, k, V)
		end
	end

	-- skip cache
	local postResponse, status, isError = self.webclient:post(postUrl, payload, true)
	
	if (isError ~= true) then
        -- this is looking for the postId
		local newPostId =  string.match(self.webclient:getLastUrl(), "p=(%d+)$")
        
		if (not newPostId) then
			-- If we're in there then we were not able to get the threadId of the
            -- the thread we just committe           
            
			local errorText = self:getPostErrorText(postResponse)
			error.throw({ 
				["error-text"] = errorText, 
				["html"] = pageSrc,
				["url"] = prePostUrl,				
			})         
            
			return nil
		end
        
		return newPostId
	else
        error.throw({ 
            ["error-text"] = "There was an unknown error submitting the post"
        }) 
	end
	
	return nil
end 

--- Submits a new thread to the specified forum.
-- This function will return the error text from the message board if
-- the submit fails. This function returns the postId of the first 
-- post in the thread instead of the threadId.
-- @param threadInfo A table with the new thread info.
-- @field threadInfo["forumId"] The Id of the forum to which the thread is to be posted.
-- @field threadInfo["title"] The title of the new thread.
-- @field threadInfo["text"] The body text of the first post of the thread.
-- @field threadInfo["taglist"] A comma seprated list of tags.
-- @return The postId of the first post of the new thread.
function Parser:doSubmitNewThread(threadInfo)
	local prePostUrl = string.format("%s/newthread.php?do=newthread&f=%s",
		self.baseUrl, threadInfo["forumId"])

	local postParams = {}
	
	do
		local pageSrc, status, isError = self.webclient:get(prePostUrl, true)	
		local preDoc = sgml.new(pageSrc)
		local formTags = preDoc:getElementsByName("form","name","vbform")
		
		if (#formTags > 0) then
			local hiddenTags = preDoc:getElementsByName("input","type","hidden")
			for i,T in pairs(hiddenTags) do
				if (T:hasAttribute("name") and T:hasAttribute("value")) then
					local name = T:attribute("name")
					local value = T:attribute("value")
					postParams[name] = value
				end
			end
		else
			-- TODO: error, could not find vbform
			-- vbulletin will give back an error page that we can parser and report
			-- back to the user
			local errorText = self:getErrorText(pageSrc)
			error.throw({ 
				["error-text"] = errorText, 
				["html"] = pageSrc,
				["url"] = prePostUrl,				
			})
			return nil
		end
	end

	-- prepare the subject
	postParams["subject"] = escape(threadInfo["title"])
	postParams["subject"] = string.gsub(postParams["subject"], "%%20", "+")	
	
	-- prepare the message
	postParams["message"] = escape(threadInfo["text"])
	postParams["message"] = string.gsub(postParams["message"], "%%20", "+")	

	-- prepare the tags list
	postParams["taglist"] = escape(threadInfo["taglist"])
	
	postParams["signature"] = 1;
	postParams["parseurl"] = 1;
	
	local postUrl = string.format("%s/newthread.php?do=postthread&f=%s",
		self.baseUrl, threadInfo["forumId"])
		
	local payload = nil
	for k,V in pairs(postParams) do
		if (not payload) then
			payload = string.format("%s=%s", k, V)
		else
			payload = string.format("%s&%s=%s", payload, k, V)
		end
	end		
	
	local postResponse, status, isError = self.webclient:post(postUrl, payload, true)
	
	if (isError ~= true) then
    
		-- search for the new threadId (a few possibilities)
		local newThreadId = self:searchNewThreadId(postResponse)
        
		if (not newThreadId) then
			-- If we're in there then we were not able to get the threadId of the
            -- the thread we just committe           
            
			local errorText = self:getPostErrorText(postResponse)
			error.throw({ 
				["error-text"] = errorText, 
				["html"] = pageSrc,
				["url"] = prePostUrl,				
			})         
            
			return nil
		end
        
		return newThreadId
	else
        error.throw({ 
            ["error-text"] = "There was an unknown error submitting the thread"
        }) 
	end
	
	return nil	
end

function Parser:searchNewThreadId(html)
	local pattern = [[href%s*=%s*"showthread.-t=(%d+).-goto=nextoldest.-"]]
	local id = string.match(html, pattern)
	if (id ~= nil) then
		return id
	end

	pattern = [[href%s*=%s*"printthread.-t=(%d+).-"]]
	id = string.match(html, pattern)
	if (id ~= nil) then
		return id
	end		

	pattern = [[href%s*=%s*"subscription.-t=(%d+).-"]]
	id = string.match(html, pattern)
	if (id ~= nil) then
		return id
	end	

	local postDoc = sgml.new(html)
	local tags = postDoc:getElementsByName("input","id","qr_threadid")
	if (#tags > 0 and tags[1]:hasAttribute("value")) then
		return tags[1]:attribute("value")
	end	

	return nil
end

function Parser:getPostErrorText(html)
    -- utils.debug(html)
	local pattern = [[<!%-%-POSTERROR do not remove this comment%-%->(.-)<!%-%-/POSTERROR do not remove this comment%-%->]]
    local text = html:match(pattern)
        
    if (text ~= nil) then
        local postDoc = sgml.new(text)
        local tags = postDoc:getElementsByName("li",nil, nil)
        if (#tags > 0) then
            return postDoc:getText(tags[1])
        end
    
        return text
    end
    
    return nil
end

function Parser:getErrorText(html)
	local pattern = [[<!%-%- main error message %-%->(.-)<!%-%- / main error message %-%->]]
	local text = string.match(html, pattern)
	
	if (text ~= nil) then
		-- TODO:#bug "Log Out" and "Home" are links inside the <div> table
		-- between the Html comment above that DO NOT get parsed out,this 
		-- results in quirky error message from vbulletin
		return utils.stripHtml(text)
	end

	-- forgot when this shows up
	local doc = sgml.new(html)
	local tags = doc:getElementsByName("div", "class", "panel")
	if (#tags > 0) then
		local text = string.sub(html,tags[1]:startPos(),tags[1]:endPos() + tags[1]:endLen() + 1)	
		return utils.stripHtml(text)
	end

	return nil
end

function Parser:doMarkForumRead(forumId)
	local markreadhash = "";
	if (self.securityToken ~= nil and #self.securityToken > 0) then
		markreadhash = string.format("markreadhash=%s", self.securityToken)
	end

	local url = string.format("%s/forumdisplay.php?do=markread&%s",
		self.baseUrl, markreadhash)

	if (forumId ~= self.rootForumId) then
		url = string.format("%s&f=%s", url, forumId)
	end
	
	local pageSrc, status, isError = self.webclient:get(url, true)
	
	if (isError or string.len(pageSrc) == 0) then
		-- TODO: error, no return html from marking forum read
		return false
	end
	
	return true	
end

function Parser:htmlToBBCode(html)
	return html
end

-- Constructs a [QUOTE] string from the specified
-- post information. 
function Parser:getPostQuote(postInfo)
	local quote
	local url = string.format("%s/newreply.php?do=newreply&p=%s", 
		self.baseUrl, postInfo["postId"])

	local pageSrc, status, isError = self.webclient:get(url, true)	
	if (isError == false) then
		local doc = sgml.new(pageSrc);
		local taElements = doc:getElementsByName("textarea","name","message");

		if (#taElements > 0 and #(taElements[1]:children()) > 0) then
			quote = taElements[1]:children()[1]:value() .. "\n\n"
		end
	end

	if (isError or string.len(quote) == 0) then
		if (postInfo["postText"] > 0) then
			if (string.len(postInfo["postAuthor"]) > 0 and string.len(postInfo["postId"]) > 0) then
				quote = string.format("[QUOTE=%s;%s]%s[/QUOTE]\n\n", 
					postInfo["postAuthor"], postInfo["postId"], postInfo["postText"]);
			else
				quote = string.form("[QUOTE]%s[/QUOTE]\n\n", postInfo["postText"]);
			end
		end
	end
	
	return quote;
end

function Parser:getLastRequestUrl()
	return self.webclient:getLastUrl()
end
