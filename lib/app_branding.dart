/// This file only defines the DEFAULT/fallback branding:
///  - Right when the app opens (Role Selector, Login screen) — no school
///    has logged in yet at this point, so it isn't possible to know
///    which school's name/logo to show. Until then, this same generic
///    name/logo is shown.
///  - If a school hasn't set Settings > School Name / School Logo yet —
///    this same fallback is used then too (throughout the app and in
///    PDFs), so an empty/broken spot is never shown.
///
/// When handing the project to a NEW SCHOOL: each school can set its own
/// actual name/logo via Settings > School Name / School Logo (without
/// touching any code) — after login, that same name/logo will show
/// throughout the app and in PDFs. This file is only for pre-login
/// screens and the "nothing set yet" fallback.
library;

const String kDefaultSchoolName = 'School Management Software';
const String kDefaultLogoAsset = 'assets/logo.png';
