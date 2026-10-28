-- NotificationSubject.lua: subject appended to a notification title in the list
stub("engine")
include("NotificationSubject")

test("own city is appended unless named already", function()
	eq(NotificationSubject_Line("NOTIFICATION_CHOOSE_PRODUCTION", "Choose Production", "Rome needs orders", "Antium", nil), "Choose Production: Antium")
	eq(NotificationSubject_Line("X", "City Needs Food", "Lugdunum needs food", "Lugdunum", nil), "City Needs Food")
end)

test("amenities: city from the summary when the notification has no usable city", function()
	eq(NotificationSubject_Line("NOTIFICATION_CITY_LOW_AMENITIES", "Need More Amenities", "Lugdunum needs more Amenities", nil, nil), "Lugdunum needs more Amenities")
end)

test("unit name", function()
	eq(NotificationSubject_Line("NOTIFICATION_UNIT_PROMOTION_AVAILABLE", "Unit available for promotion", "A unit can be promoted", nil, "Musketman"), "Unit available for promotion: Musketman")
	eq(NotificationSubject_Line("X", "Unit available for promotion", "", nil, "LOC_UNIT_FOO"), "Unit available for promotion")
end)

test("wonder and peace use the short summary", function()
	eq(NotificationSubject_Line("NOTIFICATION_WONDER_COMPLETED", "Wonder Completed", "Eiffel Tower completed in Paris", nil, nil), "Eiffel Tower completed in Paris")
	eq(NotificationSubject_Line("NOTIFICATION_NEGOTIATED_PEACE", "Negotiated Peace", "Nazca has made peace with Hong Kong", nil, nil), "Nazca has made peace with Hong Kong")
end)

test("long or unrelated summaries are not used", function()
	eq(NotificationSubject_Line("NOTIFICATION_WONDER_COMPLETED", "Wonder Completed", "one two three four five six seven eight nine ten eleven twelve thirteen", nil, nil), "Wonder Completed")
	eq(NotificationSubject_Line("NOTIFICATION_TECH_BOOST", "Eureka", "You got a boost", nil, nil), "Eureka")
end)

test("summary that already holds the title replaces it", function()
	eq(NotificationSubject_Line("NOTIFICATION_CITY_LOW_AMENITIES", "Need More Amenities", "Need More Amenities in Rome", nil, nil), "Need More Amenities in Rome")
end)
