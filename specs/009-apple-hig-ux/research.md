# Apple HIG Research and Design Decisions

Reviewed 2026-10-05 against Apple primary documentation. HIG pages are JavaScript-rendered; official indexed guidance and developer documentation informed this planning review. Recheck guidance when implementing; document guidance versus CamLid-specific choices separately.

## 1. Native menu bar and compact dashboard

**Decision**: Keep left-click dashboard/right-click options; offer all options via dashboard and keyboard as well. Use a template status symbol, concise native menu commands, task grouping and one anchored transient surface.
**Rationale**: Apple's [menu bar guidance](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) and [menus](https://developer.apple.com/design/human-interface-guidelines/menus) favor familiar command access. [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) and its [window style](https://developer.apple.com/documentation/swiftui/menubarextrastyle/window) provide native data-rich utility patterns. [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) support a focused transient task surface.
**Alternatives**: Full always-open dashboard increases interruption; secondary-click-only commands reduce discoverability. Do not replace existing AppKit routing merely to use a newer API if it loses requested behavior.

## 2. Settings and window behavior

**Decision**: Native separate Settings window with standard Settings…/Command-comma, purpose-based groups and restored selected section; explicit draft/discard behavior. Prefer native toolbar/pane navigation where supported.
**Rationale**: [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) separates app preferences from global system preferences. [Windows](https://developer.apple.com/design/human-interface-guidelines/windows) and [layout](https://developer.apple.com/design/human-interface-guidelines/layout) guide familiar chrome and adaptation. General/Agents/Safety/Activity grouping is a CamLid product choice, not an Apple-mandated taxonomy.
**Alternatives**: A single dense form obscures common settings; custom chrome or system appearance overrides add unfamiliar behavior. Save controls are retained where validation/revision conflicts require explicit outcomes.

## 3. Accessibility and appearance

**Decision**: System typography and semantic colors; text/symbol equivalents, VoiceOver labels/values and full keyboard paths; respect contrast, motion and transparency preferences. Prefer existing native materials over manually imitated glass; availability fallback required.
**Rationale**: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards), [color](https://developer.apple.com/design/human-interface-guidelines/color), and [VoiceOver evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria/) support independent operation and perceivable status.
**Alternatives**: Decorative gradients/animations and color-only status add little to a utility and complicate accessibility. HIG is guidance, not certification or proof that a particular accessibility tree works.

## 4. Truthful status hierarchy

**Decision**: Effective capability/reason and Stop precede detail; requested mode separate; preview and uncertainty explicit. Ten states and screen/layout matrix are CamLid acceptance criteria.
**Rationale**: Native clarity and project constitution safety/evidence principles. A polished Protected badge cannot replace actual lease/readback verification.
**Alternatives**: A single mode badge conflates intent with outcome; showing every diagnostic in the first view overloads status comprehension.

No unresolved design blocker requires a new permission or external dependency. Actual UI geometry, VoiceOver behavior and HIG compliance require implementation-time native evidence. Physical support remains M1.
