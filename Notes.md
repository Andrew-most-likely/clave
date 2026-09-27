# Hyper-land OS Visual Pack: Requirements and Open Questions

 ## 1\. Apple Branding and Legal Distinction

 - Replace all Apple logos in the public release with a unique, simple shape that has similar simplicity and recognizability but is not Apple's logo.
- The personal version can continue using the Apple logo.
- The public version should allow users to change the replacement logo.
- Require users to select an image that meets the correct size and format requirements.
- Remove mentions of Apple from the operating system where they are only being used to identify the project as a copy or derivative of Apple's operating system.
- Remove Apple-specific terminology such as:
  - Apple
  - Mac
  - Other Apple-specific terms used solely to describe the imitation
- Review the Finder face and Files icon for the same issue.
- For the public release, consider replacing Apple-specific Finder/Files imagery with unique equivalents.
- Allow users to customize the replacement icon or face.
- The personal version can retain the original Apple-specific visuals.
- the symbol used as the special key indicator for apple aka the command key symbol is used a lot throughout this visual wrapper due to the fact were going apple forward   although maybe we should consider adding a setting to change this to windows based on the machines people will be using will often have the windows key or another icon

 ## 2\. Calculator

 - The calculator should not require a network connection.
- Make the calculator fully functional locally whenever possible.

 ## 3\. Login Screen

 - Fix the spacing of the buttons on the login screen.
- The three buttons below the password field are currently not evenly spaced.
- Add GUI settings for customizing the login screen.
- The settings should include things such as:
  - Background image
  - Profile picture
  - Other relevant login-screen customization
- Ideally, these settings should work similarly to the equivalent customization available in a Mac-style environment.

 ## 4\. Hyper-land Pane Indicator

 - The raw version of Hyper-land displayed numbers in the top island indicating which pane the user was currently viewing.
- Bring this back as an optional setting.
- Add the setting to System Settings.
- It should be disabled by default if the goal is to preserve the cleaner visual appearance.

 ## 5\. Background Processes and Architecture

 - Minimize background listeners, services, and functions as much as possible.
- Avoid adding unnecessary background processes just to support visual features.
- The goal should be to have no more background overhead than a normal Arch Linux installation reasonably requires.
- Every added listener or background service should have a clear purpose.
- Prioritize:
  - Low resource usage
  - Minimal attack surface
  - Minimal unnecessary processes
  - Simple architecture
  - Security

 ## 6\. Local Authentication and VS Code

 - When authenticating the login with VS Code, it prompts for weaker encryption.
- Investigate whether this indicates that the local authentication ring is incorrectly configured.
- Determine:
  - What encryption VS Code expects
  - What encryption the local authentication system currently provides
  - Whether the authentication ring is configured correctly
  - Whether the prompt can be eliminated without weakening security

 ## 7\. Formal Project Plan

 - Create a formal project plan for the visual OS before continuing to add features.
- The current development process feels somewhat like adding features incrementally without a sufficiently defined target.
- Create a document that establishes:
  - Project goals
  - Visual goals
  - Required features
  - Optional features
  - Security requirements
  - Performance requirements
  - Legal/branding requirements
  - Compatibility requirements
  - Public release requirements
  - Personal-build differences
  - Quality-of-life improvements
  - Release criteria
- The current progress is good, but the process should become more structured and token-efficient.

 ## 8\. Traffic Light Buttons

 ### General Issue

 - Some applications have two sets of window controls.
- Example:
  - Bazaar has its own title bar controls.
  - The visual pack adds another set of traffic lights.
- Do not simply remove traffic lights from applications globally.
- The goal is to preserve the traffic-light aesthetic across the system.

 ### VS Code

 - VS Code has its own:
  - Close button
  - Minimize button
  - Application title
  - Application logo
- The visual pack then adds Apple-style traffic lights to the top-left.
- This creates two sets of window controls.

 ### Proposed Solution

 - Investigate whether this can be solved globally rather than with individual application hacks.
- Ideally, applications should integrate cleanly with the visual pack's window decorations.
- If 100% compatibility is impossible:
  - Add a setting to disable the visual-pack traffic lights for specific applications.
  - Allow applications to render their own window controls when necessary.
- Determine whether this is a broader issue affecting many applications and create a general solution.

 ## 9\. System Sounds

 - Sound has already been implemented, but it should be revisited.
- Audit the system for all major audio events that the Apple-style environment normally provides.
- Determine which sounds are actually needed.
- For each sound:
  - Use a legally usable sound if possible.
  - If Apple's sounds can legally be used under the project's distribution model, document the conditions clearly.
  - Otherwise, use freely licensed sounds with a similar character.
  - If necessary, use simple default system sounds.
- This is a low-priority item compared with the other requirements.

 ## 10\. Included Software

 ### General Principle

 - The public release should ship with very few additional applications.
- It should include:
  - Everything necessary to provide the visual environment
  - Everything necessary for the features we built
  - Required hardening
  - Required security software

 ### Hardened Version

 If the hardened version is the primary public release, it should contain:

 - All completed hardening
- Required security software
- The visual environment
- Essential system functionality
- No unnecessary additional applications

 ### Non-Hardened Version

 - Should not ship with additional non-essential software.
- Applications should only be included if they are necessary for:
  - The visual experience
  - The sounds
  - The underlying Apple-style aesthetic
  - Core system functionality

 Do not bundle unrelated applications such as:

 - Spotify
- Virtual machine managers
- Other convenience applications that are not required

 ### Open Question

 - Determine whether the primary public release should be:
  - Hardened
  - Non-hardened
- Regardless of that decision, maintain a minimal software footprint.

 ## 11\. Competitive and Similar Projects

 Known projects to investigate:

 - [pearOS Arch Linux](<https://github.com/pearOS-archlinux/iso>)
- [gnomintosh](<https://github.com/jothi-prasath/gnomintosh>)

 Research additional projects that:

 - Provide a similar Apple-inspired Linux experience
- Have at least 200 GitHub stars
- Have meaningful visual, usability, or technical features worth considering

 For each relevant project, document:

 - Features
- Visual approach
- Architecture
- Customization
- Security approach
- Included applications
- Quality-of-life features
- What Hyper-land already does better
- What Hyper-land is currently missing

 ### Competitive Goal

 - Aim to cover useful features found in comparable projects where doing so:
  - Does not compromise security
  - Does not create unnecessary background processes
  - Does not add excessive software
  - Does not interfere with the core Hyper-land experience
  - Does not make the system unnecessarily complicated

 The goal is feature completeness where appropriate, not blindly copying every feature.

 ## 12\. Quality-of-Life Improvements

 - Perform a dedicated quality-of-life review of the OS wrapper.
- Look for friction in:
  - Login
  - Window management
  - Desktop interaction
  - Settings
  - Application behavior
  - Customization
  - Authentication
  - System sounds
  - Visual consistency
  - First-run experience

 ## 13\. Desktop Files

 ### Question

 - Investigate whether allowing files directly on the desktop is compatible with the Hyper-land philosophy.

 ### Current Concern

 - The Hyper-land concept seems to favor a cleaner desktop environment.
- Allowing arbitrary files on the desktop could conflict with that philosophy.

 ### Counterpoint

 - A major goal is to reproduce the Apple desktop environment as closely as practical.
- Supporting desktop files would therefore be a significant step toward that goal.

 ### Decision Needed

 Determine whether:

 - Desktop files fundamentally conflict with Hyper-land's design philosophy.
- Or whether they should be supported because desktop fidelity takes priority.

 If desktop files are implemented, the desktop should behave like a real Mac-style desktop rather than simply allowing icons to be placed on an otherwise static background.

 ## 14\. Desktop Drag-to-Select

 - The desktop currently does not support drag-to-select.
- If desktop applications/files are implemented, add drag-to-select functionality.
- The interaction should create the familiar translucent blue selection rectangle.
- The selection box should allow users to select multiple desktop items by dragging across them.

 ## 15\. High-Impact Login Screen Work

 The login screen should receive dedicated attention because it is one of the first things users see.

 Required improvements:

 - Fix button spacing.
- Add login-screen customization settings.
- Support custom backgrounds.
- Support custom profile pictures.
- Make the customization accessible through System Settings.
- Ensure the visual treatment remains consistent with the rest of Hyper-land.
- Verify that customization does not introduce unnecessary background services.

 ## 16\. Architecture Principle

 A general rule should apply to all of the above:

 > **Do not add complexity solely to reproduce an appearance.**

 Every feature should be evaluated against:

 1. Does it improve the intended experience?
2. Does it require a background service?
3. Does it introduce additional listeners?
4. Does it increase the attack surface?
5. Does it consume meaningful resources?
6. Can it be implemented locally?
7. Can it be implemented more simply?
8. Does it belong in the core system or as an optional setting?

 The visual layer should remain lightweight, secure, and maintainable while providing a highly faithful Apple-style experience.

 the drawn in apple in the console some times breaks when leaving claude and continues to draw the apple on top of the text in the console window