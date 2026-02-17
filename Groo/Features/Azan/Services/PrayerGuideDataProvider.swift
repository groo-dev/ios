//
//  PrayerGuideDataProvider.swift
//  Groo
//
//  Static prayer guide data for all 5 prayers × madhab × role × traveling.
//  Phase 1: Hanafi fiqh. Other madhabs return nil for now.
//

import Foundation

enum PrayerGuideDataProvider {

    // MARK: - Public API

    static func guide(for prayer: Prayer, madhab: FiqhMadhab, role: PrayerRole, isTraveling: Bool) -> PrayerGuideData? {
        guard !prayer.isInfoOnly else { return nil }

        switch madhab {
        case .hanafi:
            return hanafiGuide(for: prayer, role: role, isTraveling: isTraveling)
        case .shafii, .maliki, .hanbali:
            return nil
        }
    }

    // MARK: - Hanafi Guide Assembly

    private static func hanafiGuide(for prayer: Prayer, role: PrayerRole, isTraveling: Bool) -> PrayerGuideData {
        let rakats = hanafiRakats(for: prayer, isTraveling: isTraveling)
        let groups = rakats.map { unit in
            hanafiGroupGuide(prayer: prayer, unit: unit, role: role)
        }
        let notes = hanafiGeneralNotes(for: prayer, role: role, isTraveling: isTraveling)

        return PrayerGuideData(
            prayer: prayer,
            arabicName: arabicName(for: prayer),
            rakatBreakdown: rakats,
            groups: groups,
            generalNotes: notes
        )
    }

    // MARK: - Arabic Names

    private static func arabicName(for prayer: Prayer) -> String {
        switch prayer {
        case .fajr: "صلاة الفجر"
        case .dhuhr: "صلاة الظهر"
        case .asr: "صلاة العصر"
        case .maghrib: "صلاة المغرب"
        case .isha: "صلاة العشاء"
        case .sunrise, .sunset: ""
        }
    }

    // MARK: - Hanafi Rakat Breakdown

    private static func hanafiRakats(for prayer: Prayer, isTraveling: Bool) -> [RakatUnit] {
        switch prayer {
        case .fajr:
            return [
                RakatUnit(category: .sunnahMuakkadah, count: 2, timing: .before,
                          notes: "Most emphasized sunnah — even when traveling"),
                RakatUnit(category: .fard, count: 2),
            ]

        case .dhuhr:
            if isTraveling {
                return [
                    RakatUnit(category: .sunnahMuakkadah, count: 4, timing: .before,
                              notes: "Optional when traveling", isOptional: true),
                    RakatUnit(category: .fard, count: 2, notes: "Qasr: shortened from 4"),
                    RakatUnit(category: .sunnahMuakkadah, count: 2, timing: .after, isOptional: true),
                    RakatUnit(category: .nafl, count: 2, timing: .after, isOptional: true),
                ]
            }
            return [
                RakatUnit(category: .sunnahMuakkadah, count: 4, timing: .before),
                RakatUnit(category: .fard, count: 4),
                RakatUnit(category: .sunnahMuakkadah, count: 2, timing: .after),
                RakatUnit(category: .nafl, count: 2, timing: .after),
            ]

        case .asr:
            if isTraveling {
                return [
                    RakatUnit(category: .sunnahGhairMuakkadah, count: 4, timing: .before,
                              notes: "Optional when traveling", isOptional: true),
                    RakatUnit(category: .fard, count: 2, notes: "Qasr: shortened from 4"),
                ]
            }
            return [
                RakatUnit(category: .sunnahGhairMuakkadah, count: 4, timing: .before,
                          notes: "Non-emphasized; rewarded but no blame for skipping"),
                RakatUnit(category: .fard, count: 4),
            ]

        case .maghrib:
            if isTraveling {
                return [
                    RakatUnit(category: .fard, count: 3, notes: "Not shortened — Maghrib is always 3"),
                    RakatUnit(category: .sunnahMuakkadah, count: 2, timing: .after, isOptional: true),
                    RakatUnit(category: .nafl, count: 2, timing: .after, isOptional: true),
                ]
            }
            return [
                RakatUnit(category: .fard, count: 3),
                RakatUnit(category: .sunnahMuakkadah, count: 2, timing: .after),
                RakatUnit(category: .nafl, count: 2, timing: .after),
            ]

        case .isha:
            if isTraveling {
                return [
                    RakatUnit(category: .sunnahGhairMuakkadah, count: 4, timing: .before,
                              notes: "Optional when traveling", isOptional: true),
                    RakatUnit(category: .fard, count: 2, notes: "Qasr: shortened from 4"),
                    RakatUnit(category: .sunnahMuakkadah, count: 2, timing: .after, isOptional: true),
                    RakatUnit(category: .nafl, count: 2, timing: .after, isOptional: true),
                    RakatUnit(category: .wajib, count: 3, timing: .after, notes: "Witr — remains wajib even when traveling"),
                ]
            }
            return [
                RakatUnit(category: .sunnahGhairMuakkadah, count: 4, timing: .before,
                          notes: "Non-emphasized; rewarded but no blame for skipping"),
                RakatUnit(category: .fard, count: 4),
                RakatUnit(category: .sunnahMuakkadah, count: 2, timing: .after),
                RakatUnit(category: .nafl, count: 2, timing: .after),
                RakatUnit(category: .wajib, count: 3, timing: .after, notes: "Witr — wajib in Hanafi fiqh"),
            ]

        case .sunrise, .sunset:
            return []
        }
    }

    // MARK: - Per-Group Guide Builder

    private static func hanafiGroupGuide(prayer: Prayer, unit: RakatUnit, role: PrayerRole) -> RakatGroupGuide {
        // Non-fard groups are always prayed alone
        let effectiveRole: PrayerRole = unit.category == .fard ? role : .munfarid
        let mode = recitationMode(prayer: prayer, unit: unit)
        let title = groupDisplayTitle(prayer: prayer, unit: unit)
        let niyyah = groupNiyyah(prayer: prayer, unit: unit, role: effectiveRole)
        let rakats = hanafiRakatDetails(prayer: prayer, unit: unit, role: effectiveRole, mode: mode)
        let notes = groupNotes(prayer: prayer, unit: unit)

        return RakatGroupGuide(
            unit: unit,
            displayTitle: title,
            niyyah: niyyah,
            recitationMode: mode,
            rakats: rakats,
            notes: notes
        )
    }

    // MARK: - Group Display Title

    private static func groupDisplayTitle(prayer: Prayer, unit: RakatUnit) -> String {
        let count = unit.count
        let category = unit.category.displayName

        switch unit.timing {
        case .before:
            return "\(count) \(category) · Before"
        case .after:
            if unit.category == .wajib {
                return "\(count) Witr \(category)"
            }
            return "\(count) \(category) · After"
        case .main:
            if unit.category == .wajib {
                return "\(count) Witr \(category)"
            }
            return "\(count) \(category)"
        }
    }

    // MARK: - Recitation Mode

    private static func recitationMode(prayer: Prayer, unit: RakatUnit) -> RecitationMode {
        switch unit.category {
        case .sunnahMuakkadah, .sunnahGhairMuakkadah, .nafl:
            return .silent
        case .fard:
            switch prayer {
            case .fajr, .maghrib, .isha: return .aloud
            case .dhuhr, .asr: return .silent
            case .sunrise, .sunset: return .silent
            }
        case .wajib:
            return .silent
        }
    }

    // MARK: - Per-Group Niyyah

    private static func groupNiyyah(prayer: Prayer, unit: RakatUnit, role: PrayerRole) -> NiyyahText {
        let count = unit.count
        let prayerArabicName = arabicNiyyahName(for: prayer)
        let prayerEnglish = prayer.displayName.lowercased()

        let categoryArabic: String
        let categoryTranslit: String
        let categoryEnglish: String

        switch unit.category {
        case .sunnahMuakkadah:
            categoryArabic = "سُنَّةَ"
            categoryTranslit = "sunnata"
            categoryEnglish = "sunnah mu'akkadah of"
        case .sunnahGhairMuakkadah:
            categoryArabic = "سُنَّةَ"
            categoryTranslit = "sunnata"
            categoryEnglish = "sunnah ghair mu'akkadah of"
        case .fard:
            categoryArabic = "فَرْضَ اللَّهِ تَعَالَى"
            categoryTranslit = "farḍa Allāhi ta'ālā"
            categoryEnglish = "fard prayer of"
        case .wajib:
            categoryArabic = "وَاجِبَ"
            categoryTranslit = "wājiba"
            categoryEnglish = "wajib (Witr) of"
        case .nafl:
            categoryArabic = "نَفْلاً"
            categoryTranslit = "naflan"
            categoryEnglish = "nafl after"
        }

        let roleArabic = unit.category == .fard ? niyyahRoleArabic(role) : ""
        let roleTranslit = unit.category == .fard ? niyyahRoleTransliteration(role) : ""
        let roleEnglish = unit.category == .fard ? niyyahRoleEnglish(role) : ""

        let arabic = "نَوَيْتُ أَنْ أُصَلِّيَ \(count) رَكَعَاتِ صَلَاةِ \(prayerArabicName) \(categoryArabic)\(roleArabic) مُتَوَجِّهًا إِلَى جِهَةِ الْكَعْبَةِ الشَّرِيفَةِ اللَّهُ أَكْبَرُ"

        let translit = "Nawaitu an usalliya \(count) raka'āti ṣalāt al-\(prayerEnglish) \(categoryTranslit)\(roleTranslit) mutawajjihan ilā jihat al-Ka'bati ash-sharīfah. Allāhu Akbar."

        let english = "I intend to pray \(count) rak'ahs \(categoryEnglish) \(prayer.displayName)\(roleEnglish), facing the Ka'bah. Allah is the Greatest."

        return NiyyahText(arabic: arabic, transliteration: translit, english: english)
    }

    private static func arabicNiyyahName(for prayer: Prayer) -> String {
        switch prayer {
        case .fajr: "الْفَجْرِ"
        case .dhuhr: "الظُّهْرِ"
        case .asr: "الْعَصْرِ"
        case .maghrib: "الْمَغْرِبِ"
        case .isha: "الْعِشَاءِ"
        case .sunrise, .sunset: ""
        }
    }

    private static func niyyahRoleArabic(_ role: PrayerRole) -> String {
        switch role {
        case .munfarid: ""
        case .imam: " إِمَامًا"
        case .muqtadi: " خَلْفَ هَذَا الْإِمَامِ"
        }
    }

    private static func niyyahRoleTransliteration(_ role: PrayerRole) -> String {
        switch role {
        case .munfarid: ""
        case .imam: " imāman"
        case .muqtadi: " khalfa hādha al-imām"
        }
    }

    private static func niyyahRoleEnglish(_ role: PrayerRole) -> String {
        switch role {
        case .munfarid: ""
        case .imam: ", as imam"
        case .muqtadi: ", behind this imam"
        }
    }

    // MARK: - Shared Action Factories

    private static func takbirAction() -> RakatAction {
        RakatAction(
            name: "Takbīr al-Iḥrām",
            arabicText: "اللَّهُ أَكْبَرُ",
            transliteration: "Allāhu Akbar",
            instruction: "Raise both hands to ear level and say the opening takbīr.",
            icon: "hands.sparkles",
            posture: .handsRaised
        )
    }

    private static func thanaAction() -> RakatAction {
        RakatAction(
            name: "Thanā' (Opening Supplication)",
            arabicText: "سُبْحَانَكَ اللَّهُمَّ وَبِحَمْدِكَ وَتَبَارَكَ اسْمُكَ وَتَعَالَى جَدُّكَ وَلَا إِلَهَ غَيْرُكَ",
            transliteration: "Subḥānaka Allāhumma wa biḥamdik, wa tabāraka-smuk, wa ta'ālā jadduk, wa lā ilāha ghayruk",
            instruction: "Recite silently with hands folded below the navel.",
            icon: "text.book.closed",
            posture: .standing
        )
    }

    private static func taawwudhAction(role: PrayerRole) -> RakatAction {
        RakatAction(
            name: "Ta'awwudh & Basmalah",
            arabicText: "أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ · بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ",
            transliteration: "A'ūdhu billāhi min ash-shayṭān ir-rajīm · Bismillāh ir-Raḥmān ir-Raḥīm",
            instruction: role == .muqtadi
                ? "The muqtadi remains silent — the imam recites."
                : "Seek refuge in Allah, then begin with the name of Allah.",
            icon: "shield"
        )
    }

    private static func fatihaAction(role: PrayerRole, mode: RecitationMode) -> RakatAction {
        if role == .muqtadi {
            return RakatAction(
                name: "Qiyām (Stand Silently)",
                instruction: "In Hanafi fiqh, the muqtadi does NOT recite al-Fātiḥah behind the imam. Stand silently.",
                icon: "person.fill"
            )
        }
        return RakatAction(
            name: "Sūrah al-Fātiḥah",
            arabicText: "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ...",
            transliteration: "Al-ḥamdu lillāhi Rabb il-'ālamīn...",
            instruction: mode == .aloud
                ? "Recite Sūrah al-Fātiḥah aloud. Say Āmīn silently at the end."
                : "Recite Sūrah al-Fātiḥah silently. Say Āmīn silently at the end.",
            icon: "book",
            isAloud: mode == .aloud
        )
    }

    private static func surahAction(mode: RecitationMode, role: PrayerRole) -> RakatAction {
        if role == .muqtadi {
            return RakatAction(
                name: "Additional Sūrah",
                instruction: "Stand silently while the imam recites.",
                icon: "book.pages"
            )
        }
        return RakatAction(
            name: "Additional Sūrah",
            instruction: mode == .aloud
                ? "Recite any sūrah or at least 3 short āyahs aloud after al-Fātiḥah."
                : "Recite any sūrah or at least 3 short āyahs silently after al-Fātiḥah.",
            icon: "book.pages",
            isAloud: mode == .aloud
        )
    }

    private static func rukuAction() -> RakatAction {
        RakatAction(
            name: "Rukū' (Bowing)",
            arabicText: "سُبْحَانَ رَبِّيَ الْعَظِيمِ",
            transliteration: "Subḥāna Rabbiyal-'Aẓīm",
            instruction: "Say \"Allāhu Akbar\" and bow. Say the tasbīḥ at least 3 times.",
            icon: "figure.flexibility",
            posture: .bowing
        )
    }

    private static func qawmahAction(role: PrayerRole) -> RakatAction {
        RakatAction(
            name: "Qawmah (Rising)",
            arabicText: role == .imam
                ? "سَمِعَ اللَّهُ لِمَنْ حَمِدَهُ"
                : "رَبَّنَا لَكَ الْحَمْدُ",
            transliteration: role == .imam
                ? "Sami' Allāhu liman ḥamidah"
                : "Rabbanā lakal-ḥamd",
            instruction: role == .imam
                ? "Say aloud while rising. The congregation responds \"Rabbanā lakal-ḥamd.\""
                : role == .muqtadi
                    ? "When the imam says \"Sami' Allāhu liman ḥamidah,\" respond \"Rabbanā lakal-ḥamd.\""
                    : "Say \"Sami' Allāhu liman ḥamidah\" while rising, then \"Rabbanā lakal-ḥamd.\"",
            icon: "arrow.up",
            posture: .standingBrief
        )
    }

    private static func sujudAction() -> RakatAction {
        RakatAction(
            name: "Sujūd (Prostration × 2)",
            arabicText: "سُبْحَانَ رَبِّيَ الْأَعْلَى",
            transliteration: "Subḥāna Rabbiyal-A'lā",
            instruction: "Prostrate on 7 body parts. Say tasbīḥ at least 3 times. Sit briefly (jalsah), then repeat.",
            icon: "arrow.down.to.line",
            posture: .prostrating
        )
    }

    private static func tashahhudAction() -> RakatAction {
        RakatAction(
            name: "Tashahhud",
            arabicText: "التَّحِيَّاتُ لِلَّهِ وَالصَّلَوَاتُ وَالطَّيِّبَاتُ...",
            transliteration: "At-taḥiyyātu lillāhi waṣ-ṣalawātu waṭ-ṭayyibāt...",
            instruction: "Sit and recite at-Tashahhud. Raise index finger during the shahādah.",
            icon: "hand.point.up",
            posture: .sitting
        )
    }

    private static func duroodAction() -> RakatAction {
        RakatAction(
            name: "Durūd (Ṣalawāt)",
            arabicText: "اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَعَلَى آلِ مُحَمَّدٍ...",
            transliteration: "Allāhumma ṣalli 'alā Muḥammad wa 'alā āli Muḥammad...",
            instruction: "Recite Durūd Ibrāhīm after tashahhud in the final sitting.",
            icon: "star"
        )
    }

    private static func duaAction() -> RakatAction {
        RakatAction(
            name: "Du'ā' before Salām",
            arabicText: "رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ",
            transliteration: "Rabbanā ātinā fid-dunyā ḥasanah wa fil-ākhirati ḥasanah wa qinā 'adhāb an-nār",
            instruction: "Make a brief supplication from Qur'an or Sunnah.",
            icon: "hands.and.sparkles"
        )
    }

    private static func salamAction() -> RakatAction {
        RakatAction(
            name: "Salām",
            arabicText: "السَّلَامُ عَلَيْكُمْ وَرَحْمَةُ اللَّهِ",
            transliteration: "As-salāmu 'alaykum wa raḥmatullāh",
            instruction: "Turn head right and say salām, then turn left. This ends the prayer.",
            icon: "hand.wave",
            posture: .salam
        )
    }

    private static func qunutAction() -> RakatAction {
        RakatAction(
            name: "Qunūt (Witr Du'ā')",
            arabicText: "اللَّهُمَّ إِنَّا نَسْتَعِينُكَ وَنَسْتَغْفِرُكَ...",
            transliteration: "Allāhumma innā nasta'īnuka wa nastaghfiruk...",
            instruction: "After the additional sūrah, say \"Allāhu Akbar\" raising hands to ears, then recite Qunūt du'ā' with hands raised.",
            icon: "hands.and.sparkles",
            isSpecial: true,
            posture: .standing
        )
    }

    private static func qunutTakbirAction() -> RakatAction {
        RakatAction(
            name: "Takbīr for Qunūt",
            arabicText: "اللَّهُ أَكْبَرُ",
            transliteration: "Allāhu Akbar",
            instruction: "Raise hands to ears and say takbīr before reciting Qunūt.",
            icon: "hands.sparkles",
            isSpecial: true,
            posture: .handsRaised
        )
    }

    private static func standForNextAction() -> RakatAction {
        RakatAction(
            name: "Stand for next rak'ah",
            instruction: "Say \"Allāhu Akbar\" and stand up for the next rak'ah.",
            icon: "arrow.up.circle"
        )
    }

    // MARK: - Rakat Detail Builders

    private static func hanafiRakatDetails(prayer: Prayer, unit: RakatUnit, role: PrayerRole, mode: RecitationMode) -> [RakatDetail] {
        let count = unit.count

        if unit.category == .wajib {
            return witrRakatDetails(role: role, mode: mode)
        }

        switch count {
        case 2:
            return twoRakatDetails(role: role, mode: mode, isFard: unit.category == .fard)
        case 3:
            return threeRakatFardDetails(prayer: prayer, role: role, mode: mode)
        case 4:
            return fourRakatDetails(role: role, mode: mode, isFard: unit.category == .fard)
        default:
            return []
        }
    }

    // MARK: 2-Rakat Pattern

    private static func twoRakatDetails(role: PrayerRole, mode: RecitationMode, isFard: Bool) -> [RakatDetail] {
        let rakat1 = RakatDetail(number: 1, actions: [
            takbirAction(),
            thanaAction(),
            taawwudhAction(role: role),
            fatihaAction(role: role, mode: mode),
            role == .muqtadi ? nil : surahAction(mode: mode, role: role),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            standForNextAction(),
        ].compactMap { $0 })

        let rakat2 = RakatDetail(number: 2, actions: [
            fatihaAction(role: role, mode: mode),
            role == .muqtadi ? nil : surahAction(mode: mode, role: role),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            tashahhudAction(),
            duroodAction(),
            duaAction(),
            salamAction(),
        ].compactMap { $0 }, sittingType: .finalTashahhud)

        return [rakat1, rakat2]
    }

    // MARK: 3-Rakat Maghrib Fard

    private static func threeRakatFardDetails(prayer: Prayer, role: PrayerRole, mode: RecitationMode) -> [RakatDetail] {
        // Maghrib fard: first 2 aloud, 3rd silent
        let aloudMode: RecitationMode = (prayer == .maghrib) ? .aloud : mode
        let silentMode: RecitationMode = .silent

        let rakat1 = RakatDetail(number: 1, actions: [
            takbirAction(),
            thanaAction(),
            taawwudhAction(role: role),
            fatihaAction(role: role, mode: aloudMode),
            role == .muqtadi ? nil : surahAction(mode: aloudMode, role: role),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            standForNextAction(),
        ].compactMap { $0 })

        let rakat2 = RakatDetail(number: 2, actions: [
            fatihaAction(role: role, mode: aloudMode),
            role == .muqtadi ? nil : surahAction(mode: aloudMode, role: role),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            tashahhudAction(),
            standForNextAction(),
        ].compactMap { $0 }, sittingType: .midTashahhud)

        let rakat3 = RakatDetail(number: 3, actions: [
            fatihaAction(role: role, mode: silentMode),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            tashahhudAction(),
            duroodAction(),
            duaAction(),
            salamAction(),
        ], sittingType: .finalTashahhud)

        return [rakat1, rakat2, rakat3]
    }

    // MARK: 4-Rakat Pattern

    private static func fourRakatDetails(role: PrayerRole, mode: RecitationMode, isFard: Bool) -> [RakatDetail] {
        // For 4-rakat fard of Isha: first 2 aloud, last 2 silent
        // For other 4-rakat (Dhuhr/Asr fard, sunnah): all silent
        let firstTwoMode = mode
        let lastTwoMode: RecitationMode = .silent

        let rakat1 = RakatDetail(number: 1, actions: [
            takbirAction(),
            thanaAction(),
            taawwudhAction(role: role),
            fatihaAction(role: role, mode: firstTwoMode),
            role == .muqtadi ? nil : surahAction(mode: firstTwoMode, role: role),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            standForNextAction(),
        ].compactMap { $0 })

        let rakat2 = RakatDetail(number: 2, actions: [
            fatihaAction(role: role, mode: firstTwoMode),
            role == .muqtadi ? nil : surahAction(mode: firstTwoMode, role: role),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            tashahhudAction(),
            standForNextAction(),
        ].compactMap { $0 }, sittingType: .midTashahhud)

        // Rakats 3-4: Fatiha only for fard, Fatiha + Surah for sunnah
        let rakat3 = RakatDetail(number: 3, actions: {
            var actions: [RakatAction] = [fatihaAction(role: role, mode: lastTwoMode)]
            if !isFard && role != .muqtadi {
                actions.append(surahAction(mode: lastTwoMode, role: role))
            }
            actions.append(contentsOf: [
                rukuAction(),
                qawmahAction(role: role),
                sujudAction(),
                standForNextAction(),
            ])
            return actions
        }())

        let rakat4 = RakatDetail(number: 4, actions: {
            var actions: [RakatAction] = [fatihaAction(role: role, mode: lastTwoMode)]
            if !isFard && role != .muqtadi {
                actions.append(surahAction(mode: lastTwoMode, role: role))
            }
            actions.append(contentsOf: [
                rukuAction(),
                qawmahAction(role: role),
                sujudAction(),
                tashahhudAction(),
                duroodAction(),
                duaAction(),
                salamAction(),
            ])
            return actions
        }(), sittingType: .finalTashahhud)

        return [rakat1, rakat2, rakat3, rakat4]
    }

    // MARK: 3-Rakat Witr

    private static func witrRakatDetails(role: PrayerRole, mode: RecitationMode) -> [RakatDetail] {
        let rakat1 = RakatDetail(number: 1, actions: [
            takbirAction(),
            thanaAction(),
            taawwudhAction(role: role),
            fatihaAction(role: role, mode: mode),
            surahAction(mode: mode, role: role),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            standForNextAction(),
        ])

        let rakat2 = RakatDetail(number: 2, actions: [
            fatihaAction(role: role, mode: mode),
            surahAction(mode: mode, role: role),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            tashahhudAction(),
            standForNextAction(),
        ], sittingType: .midTashahhud)

        let rakat3 = RakatDetail(number: 3, actions: [
            fatihaAction(role: role, mode: mode),
            surahAction(mode: mode, role: role),
            qunutTakbirAction(),
            qunutAction(),
            rukuAction(),
            qawmahAction(role: role),
            sujudAction(),
            tashahhudAction(),
            duroodAction(),
            duaAction(),
            salamAction(),
        ], sittingType: .finalTashahhud)

        return [rakat1, rakat2, rakat3]
    }

    // MARK: - Per-Group Notes

    private static func groupNotes(prayer: Prayer, unit: RakatUnit) -> [String] {
        var notes: [String] = []

        switch unit.category {
        case .sunnahMuakkadah:
            if prayer == .fajr && unit.timing == .before {
                notes.append("Most emphasized sunnah — the Prophet ﷺ never left it, even when traveling.")
                notes.append("Recommended sūrahs: al-Kāfirūn (109) in rak'ah 1, al-Ikhlāṣ (112) in rak'ah 2.")
            }
            if prayer == .dhuhr && unit.timing == .before {
                notes.append("4 rak'ahs prayed with one salām (like Dhuhr fard structure).")
            }
        case .sunnahGhairMuakkadah:
            notes.append("Non-emphasized sunnah — rewarded for praying, no blame for skipping.")
        case .fard:
            break // Fard-specific notes handled in general notes
        case .wajib:
            notes.append("Witr is wajib in Hanafi fiqh — higher obligation than sunnah.")
            notes.append("Qunūt du'ā' is recited in the 3rd rak'ah before rukū'.")
        case .nafl:
            notes.append("Voluntary prayers for extra reward.")
        }

        if unit.isOptional {
            notes.append("Optional when traveling — may be skipped without blame.")
        }

        return notes
    }

    // MARK: - General Notes (Travel, Role, etc.)

    private static func hanafiGeneralNotes(for prayer: Prayer, role: PrayerRole, isTraveling: Bool) -> [String] {
        var notes: [String] = []

        switch prayer {
        case .fajr:
            if isTraveling {
                notes.append("Fajr sunnah is still recommended even when traveling.")
            }
        case .dhuhr:
            if isTraveling {
                notes.append("Qasr: Fard shortened from 4 to 2 rak'ahs. Sunnah prayers become optional.")
            }
        case .asr:
            notes.append("No nafl prayers after Asr fard until Maghrib.")
            if isTraveling {
                notes.append("Qasr: Fard shortened from 4 to 2 rak'ahs.")
            }
        case .maghrib:
            notes.append("Maghrib is not shortened when traveling — it remains 3 fard.")
        case .isha:
            if isTraveling {
                notes.append("Qasr: Fard shortened from 4 to 2 rak'ahs. Witr remains wajib.")
            }
        default:
            break
        }

        switch role {
        case .imam:
            notes.append("As imam, recite aloud in Fajr, Maghrib (first 2), and Isha (first 2). Silent in Dhuhr and Asr.")
            notes.append("Say \"Sami' Allāhu liman ḥamidah\" aloud when rising from rukū'.")
        case .muqtadi:
            notes.append("In Hanafi fiqh, do NOT recite Surah al-Fātiḥah behind the imam — stand silently during qiyām.")
            notes.append("Follow the imam's movements. Do not move ahead of or simultaneously with the imam.")
            notes.append("If you join late (masbūq), complete the remaining rak'ahs after the imam's salām.")
        case .munfarid:
            break
        }

        if isTraveling {
            notes.append("Qasr applies when traveling approximately 48 miles (77.25 km) or more from your city.")
            notes.append("If you pray behind a resident imam while traveling, you must pray the full rak'ahs (no qasr).")
        }

        return notes
    }
}
