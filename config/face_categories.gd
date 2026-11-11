extends RefCounted

# These are classifier choices for the artwork, not identities inferred as fact.
const CATEGORIES := {
	"age range": [
		"baby", "child", "older child", "teenager",
		"young adult", "older adult",
		"elderly adult",
	],
	"gender": [
		"woman", "man", "nonbinary", "genderqueer", "genderfluid",
		"agender", "genderfluid", "agender", "demigirl", "demiboy", "trans woman",
		"trans man", "cisgender woman", "cisgender man", "two-spirit",
		"another gender",
	],
	"race": [
		"Black", "White", "Asian", "Hispanic",
		"Middle Eastern", "Indigenous American",
		"Pacific Islander", "Aboriginal Australian",
		"mixed race"
	],
	"nationality or origin": [
		"Afghan", "American", "Australian", "Bangladeshi", "Brazilian", "British",
		"Canadian", "Chinese", "Colombian", "Egyptian", "Ethiopian", "French",
		"German", "Indian", "Indonesian", "Iranian", "Iraqi", "Italian", "Japanese",
		"Kenyan", "Mexican", "Nepalese", "Nigerian", "Pakistani", "Palestinian",
		"Philippine", "Somali", "South African", "South Korean", "Syrian", "Ukrainian",
		"Vietnamese",
	],
}
