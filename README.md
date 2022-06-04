# Civilization VI - Screen Reader Access mod

[Proof of Concept video on YouTube](https://www.youtube.com/watch?v=asmt26CQf8Q)

## Introduction

Sid Meier's Civilization VI is a superb turn based empire building strategy game. It has many mechanics, systems and features to help aspiring world changing leaders work towards world domination. However, one thing it lacks, is good accessibility features to help those with low and no vision, or those who have difficulty reading large amounts of text.

This mod has been written with the aim of allowing people who use screen readers to read the text on screen and allowing them access to the UI so that they can play the game at an equal level to their piers.

## Methodology

Civilization VI modders have access to a number of gameplay mechanics and changes, but cannot integrate with systems outside of the game very well. This has posed somewhat of a challenge for outputting screen reader information to players. These restrictions include:

* Any DLL/FFI (library) calls. This means that screen reader specific calls cannot be made directly from a mod
* HTTP calls. This means that a web app (local or remote) could not be used
* Saving files to the file system, which means that messages could not be saved to a separate file and read out by an external application.
* Writing rows to a database, which means even though the database uses databases very heavily for mod changes, we cannot use this as a place to get live changes to feed to a screen reader via a separate process.

One of the few options therefore left to us is to output log messages using LUA's standard print function, which is then logged into the lua.log file in a player's Civ VI game's directory. We include a special prefix so that we do not accidentally pick up and try and read out genuine, non screenreader specific log messages.

To read this, there is a completely separate console application that has a file watch on the lua.log file. When it detects lines that match our screenreader marker, it will use a DLL call (managed by the [AccessibleOutput NuGet package](github.com/saqibS/accessibleOutput)) to tell a player's screenreader to read the message aloud.

The mod part of this application currently focuses on getting these key bits of information out to the players. This includes what plots are selected, what menu items are highlighted, what announcements and notifications occur and nearby enemies and cities. We do this by:

* When we can, intercepting in game events and reacting accordingly
* When no event exists for the event we'd like to respond to, we overwrite the existing base game front end LUA file and make our changes in there.

The latter is more time consuming (since reading and understanding the code is therefore required), as well as introduces greater risks of incompatibilities, being broken by upstream changes, and could introduce mod incompatibilities with other mods that also modify this same file. However, it is all too often necessary.

## Current blockers to release

* The AccessibleOutput package we use is currently not ported to .NET Standard, and therefore the console application will require .NET Framework. It is invisioned that this could be a blocker to some installs of the mod. Currently investigation is ongoing as to whether to proceed with this package and if so, if we can port it to .NET Standard. The project has been dormant for 7 years now, but is still actively used by other mods (such as for Stardew Access), and unlike some of its rivals, actually works on my machine.
* Having built zip for install
* Writing out mod usage and description for Steam Workshop.
* Making it abundantly clear that this is a work in progress and will not yet work for people without an ability to use the mouse. This is currently still mouse dependent and for some screen reader users this is a blocker. In these cases, we're not yet in a position to help.

## Contributing

To get this mod to the eventual end goal of this game being playable by people with all levels of sight and reading ability, it will be a significant effort, so any help is appreciated. We happily take advice, contributions and feedback.

### Development environment setup

Some of these are adaptable to personal taste (with the exception of Civ VI and the development kit).

* Base game: [Civilization VI](https://store.steampowered.com/app/289070/Sid_Meiers_Civilization_VI/)
* SDK: [Civilization VI Development Tools](https://steamdb.info/app/404350/).
* [Visual Studio](https://visualstudio.microsoft.com/) or
* [Visual Studio Code](https://code.visualstudio.com/)

Note for screen reader users: Even though Modbuddy features its own mini version of Visual Studio, the code editing windows are not accessible to screen readers. This is why you will need VS or VSCode. You will also need VS or VSCode to do any work on the ScreenReader.Console. However, Modbuddy is a good way to do any changes to the mod itself.

