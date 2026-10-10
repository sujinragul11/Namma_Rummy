class_name AccountRules
extends RefCounted
## What a new account has to give: an email address and a mobile number, both of them.
## The form checks them here before anything is sent, so the player hears at once what is
## wrong. This mirrors backend/src/validation.js; the server is the judge, so keep the two
## in step.

const MAX_EMAIL_LENGTH := 100
const EMAIL := "^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$"
## Ten digits, the first one 6 to 9, however the country is written in front.
const INDIAN_MOBILE := "^(\\+91|91|0)?[6-9][0-9]{9}$"
## Any other country: + and the country code, 8 to 15 digits in all.
const INTERNATIONAL := "^\\+[1-9][0-9]{7,14}$"


## "" if the email address will do, otherwise what to tell the player.
static func email_problem(typed: String) -> String:
	var email := typed.strip_edges()
	if email.is_empty():
		return "Enter your email address."
	if email.length() > MAX_EMAIL_LENGTH or not _matches(EMAIL, email):
		return "That email address is not valid.\n\nIt should look like name@gmail.com."
	return ""


## "" if the mobile number will do, otherwise what to tell the player.
static func phone_problem(typed: String) -> String:
	if typed.strip_edges().is_empty():
		return "Enter your mobile number."
	# People type numbers with spaces, dashes and brackets; none of those count
	var number := RegEx.create_from_string("[\\s\\-().]").sub(typed, "", true)
	if _matches(INDIAN_MOBILE, number) or _matches(INTERNATIONAL, number):
		return ""
	return "That mobile number is not valid.\n\nEnter its 10 digits, for example 9876543210. For a number outside India, start with + and the country code."


static func _matches(pattern: String, text: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null
