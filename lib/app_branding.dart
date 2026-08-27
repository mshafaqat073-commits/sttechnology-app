/// Ye file sirf DEFAULT/fallback branding define karti hai:
///  - App khulte hi (Role Selector, Login screen) — is waqt tak koi school
///    login nahi hua hota, is liye kis school ka naam/logo dikhayein ye
///    pata nahi chal sakta. Tab tak yehi generic naam/logo dikhta hai.
///  - Kisi school ne abhi tak Settings > School Name / School Logo set
///    nahi ki — tab bhi yehi fallback (poori app aur PDFs mein) use hota
///    hai, taake kabhi khaali/tooti hui jagah na dikhe.
///
/// NAYE SCHOOL ko project dete waqt: har school apna asal naam/logo
/// Settings > School Name / School Logo se khud set kar sakta hai (bina
/// code chhue) — login ke baad poori app aur PDFs mein wahi dikhega.
/// Ye file sirf pre-login screens aur "abhi tak kuch set nahi hua"
/// fallback ke liye hai.
library;

const String kDefaultSchoolName = 'AEP School System';
const String kDefaultLogoAsset = 'assets/logo.png';
