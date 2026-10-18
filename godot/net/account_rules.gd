class_name AccountRules
extends RefCounted
## What a new account has to give: a username, a mobile number from any country and a
## password. The form checks them here before anything is sent, so the player hears at once
## what is wrong. This mirrors backend/src/validation.js; the server is the judge, so keep the
## two in step.

const MAX_USERNAME_LENGTH := 20
const MIN_PASSWORD_LENGTH := 6
const CODE_LENGTH := 6
const INDIA := "+91"
## A country code as typed in its own box: + and 1 to 3 digits.
const COUNTRY_CODE := "^\\+?[1-9][0-9]{0,2}$"
## Ten digits, the first one 6 to 9.
const INDIAN_MOBILE := "^[6-9][0-9]{9}$"
## Any country: + and the country code, 8 to 15 digits in all.
const INTERNATIONAL := "^\\+[1-9][0-9]{7,14}$"


## The number to send to the server, "+919876543210", from the two boxes of the form. A number
## typed with its own + and country code in the number box keeps that country.
static func full_number(country: String, number: String) -> String:
	var digits := _bare(number)
	if digits.begins_with("+"):
		return digits
	var code := _bare(country)
	if not code.begins_with("+"):
		code = "+" + code
	# The 0 dialled in front of a number inside its own country is not part of it abroad
	# (UK 07700 900123 is +44 7700 900123); no mobile number itself starts with 0
	while digits.begins_with("0"):
		digits = digits.substr(1)
	return code + digits


## "" if the number will do, otherwise what to tell the player.
static func phone_problem(country: String, number: String) -> String:
	var digits := _bare(number)
	if digits.is_empty():
		return "Enter your mobile number."
	if not digits.begins_with("+") and not _matches(COUNTRY_CODE, _bare(country)):
		return "Enter your country code in the small box, for example +91 for India or +1 for the USA."
	var whole := full_number(country, number)
	var indian := whole.begins_with(INDIA)
	if indian and not _matches(INDIAN_MOBILE, whole.substr(INDIA.length())):
		return "That mobile number is not valid.\n\nAn Indian mobile number has 10 digits and starts with 6, 7, 8 or 9."
	if not _matches(INTERNATIONAL, whole):
		return "That mobile number is not valid.\n\nCheck the country code and the number."
	if looks_made_up(whole):
		return "That does not look like a real mobile number.\n\nEnter your own number: we send a code to it by SMS."
	return ""


## "" if the password will do, otherwise what to tell the player.
static func password_problem(password: String) -> String:
	if password.is_empty():
		return "Enter a password."
	if password.length() < MIN_PASSWORD_LENGTH:
		return "Choose a password of at least %d characters." % MIN_PASSWORD_LENGTH
	return ""


## "" if `code` is the six digits of an SMS code, otherwise what to tell the player.
static func code_problem(code: String) -> String:
	var digits := code.replace(" ", "")
	if digits.length() != CODE_LENGTH or not digits.is_valid_int():
		return "Enter the %d-digit code from the SMS." % CODE_LENGTH
	return ""


## True for numbers people type when they do not want to give theirs: one digit over and over
## (9999999999), a short pattern repeated (9898989898) or a straight run of digits (9876543210).
## Only the last ten digits count, not the country code.
static func looks_made_up(number: String) -> bool:
	var digits := number.right(10)
	for period in range(1, 4):
		var pattern := digits.substr(0, period)
		if pattern.repeat(ceili(digits.length() / float(period))).begins_with(digits):
			return true
	var up := true
	var down := true
	for index in range(1, digits.length()):
		var step := (int(digits[index]) - int(digits[index - 1]) + 10) % 10
		up = up and step == 1
		down = down and step == 9
	return up or down


## A stored number as people read it: "+91 98765 43210" for India, any other as it is.
static func display_phone(stored: String) -> String:
	if stored.is_empty() or stored.begins_with("+"):
		return stored
	return "+91 %s %s" % [stored.substr(0, 5), stored.substr(5)]


# The number without the spaces, dashes and brackets people type in it.
static func _bare(typed: String) -> String:
	return RegEx.create_from_string("[\\s\\-().]").sub(typed.strip_edges(), "", true)


static func _matches(pattern: String, text: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null
