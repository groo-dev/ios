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

    // MARK: - Essential Recitations

    static func essentialRecitations() -> [PrayerRecitation] {
        [
            PrayerRecitation(
                id: "thana",
                name: "Thanā' (Opening Supplication)",
                arabicText: "سُبْحَانَكَ اللَّهُمَّ وَبِحَمْدِكَ وَتَبَارَكَ اسْمُكَ وَتَعَالَىٰ جَدُّكَ وَلَا إِلَٰهَ غَيْرُكَ",
                transliteration: "Subḥānaka Allāhumma wa biḥamdika, wa tabāraka-smuka, wa ta'ālā jadduka, wa lā ilāha ghayruk.",
                translation: "Glory be to You, O Allah, and praise be to You. Blessed is Your name and exalted is Your majesty, and there is no god but You.",
                usedIn: "First rak'ah only",
                audioFileName: "recitation-thana"
            ),
            PrayerRecitation(
                id: "taawwudh",
                name: "Ta'awwudh & Bismillah",
                arabicText: "أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ\nبِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
                transliteration: "A'ūdhu billāhi min ash-shayṭān ir-rajīm.\nBismillāh ir-Raḥmān ir-Raḥīm.",
                translation: "I seek refuge in Allah from the accursed Satan.\nIn the name of Allah, the Most Gracious, the Most Merciful.",
                usedIn: "First rak'ah only",
                audioFileName: nil
            ),
            PrayerRecitation(
                id: "fatiha",
                name: "Sūrah al-Fātiḥah",
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ
                    الرَّحْمَٰنِ الرَّحِيمِ
                    مَالِكِ يَوْمِ الدِّينِ
                    إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ
                    اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ
                    صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ
                    """,
                transliteration: """
                    Bismillāh ir-Raḥmān ir-Raḥīm.
                    Al-ḥamdu lillāhi Rabb il-'ālamīn.
                    Ar-Raḥmān ir-Raḥīm.
                    Māliki yawm id-dīn.
                    Iyyāka na'budu wa iyyāka nasta'īn.
                    Ihdinā aṣ-ṣirāṭ al-mustaqīm.
                    Ṣirāṭ alladhīna an'amta 'alayhim, ghayr il-maghḍūbi 'alayhim wa lā aḍ-ḍāllīn.
                    """,
                translation: """
                    In the name of Allah, the Most Gracious, the Most Merciful.
                    All praise is due to Allah, Lord of all the worlds.
                    The Most Gracious, the Most Merciful.
                    Master of the Day of Judgment.
                    You alone we worship, and You alone we ask for help.
                    Guide us on the Straight Path.
                    The path of those You have blessed, not of those who earned anger, nor of those who went astray.
                    """,
                usedIn: "Every rak'ah",
                audioFileName: "recitation-fatiha"
            ),
            PrayerRecitation(
                id: "ruku",
                name: "Rukū' Tasbīḥ",
                arabicText: "سُبْحَانَ رَبِّيَ الْعَظِيمِ",
                transliteration: "Subḥāna Rabbiyal-'Aẓīm.",
                translation: "Glory be to my Lord, the Almighty. (Say at least 3 times)",
                usedIn: "Every rak'ah",
                audioFileName: "recitation-ruku"
            ),
            PrayerRecitation(
                id: "qawmah",
                name: "Qawmah (Tasmī' & Taḥmīd)",
                arabicText: "سَمِعَ اللَّهُ لِمَنْ حَمِدَهُ\nرَبَّنَا لَكَ الْحَمْدُ",
                transliteration: "Sami' Allāhu liman ḥamidah.\nRabbanā lakal-ḥamd.",
                translation: "Allah hears whoever praises Him.\nOur Lord, to You belongs all praise.",
                usedIn: "Every rak'ah",
                audioFileName: "recitation-qawmah"
            ),
            PrayerRecitation(
                id: "sujud",
                name: "Sujūd Tasbīḥ",
                arabicText: "سُبْحَانَ رَبِّيَ الْأَعْلَىٰ",
                transliteration: "Subḥāna Rabbiyal-A'lā.",
                translation: "Glory be to my Lord, the Most High. (Say at least 3 times in each prostration)",
                usedIn: "Every rak'ah (×2)",
                audioFileName: "recitation-sujud"
            ),
            PrayerRecitation(
                id: "tashahhud",
                name: "Tashahhud (At-Taḥiyyāt)",
                arabicText: """
                    التَّحِيَّاتُ لِلَّهِ وَالصَّلَوَاتُ وَالطَّيِّبَاتُ
                    السَّلَامُ عَلَيْكَ أَيُّهَا النَّبِيُّ وَرَحْمَةُ اللَّهِ وَبَرَكَاتُهُ
                    السَّلَامُ عَلَيْنَا وَعَلَىٰ عِبَادِ اللَّهِ الصَّالِحِينَ
                    أَشْهَدُ أَنْ لَا إِلَٰهَ إِلَّا اللَّهُ وَأَشْهَدُ أَنَّ مُحَمَّدًا عَبْدُهُ وَرَسُولُهُ
                    """,
                transliteration: """
                    At-taḥiyyātu lillāhi waṣ-ṣalawātu waṭ-ṭayyibāt.
                    As-salāmu 'alayka ayyuhan-Nabiyyu wa raḥmatullāhi wa barakātuh.
                    As-salāmu 'alaynā wa 'alā 'ibādillāh iṣ-ṣāliḥīn.
                    Ash-hadu an lā ilāha illallāh, wa ash-hadu anna Muḥammadan 'abduhū wa rasūluh.
                    """,
                translation: """
                    All verbal prayers, physical prayers, and monetary worship are for Allah.
                    Peace be upon you, O Prophet, and the mercy of Allah and His blessings.
                    Peace be upon us and upon the righteous servants of Allah.
                    I bear witness that there is no god but Allah, and I bear witness that Muhammad is His servant and messenger.
                    """,
                usedIn: "Every sitting",
                audioFileName: "recitation-tashahhud"
            ),
            PrayerRecitation(
                id: "durood",
                name: "Durūd Ibrāhīm",
                arabicText: """
                    اللَّهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ وَعَلَىٰ آلِ مُحَمَّدٍ كَمَا صَلَّيْتَ عَلَىٰ إِبْرَاهِيمَ وَعَلَىٰ آلِ إِبْرَاهِيمَ إِنَّكَ حَمِيدٌ مَجِيدٌ
                    اللَّهُمَّ بَارِكْ عَلَىٰ مُحَمَّدٍ وَعَلَىٰ آلِ مُحَمَّدٍ كَمَا بَارَكْتَ عَلَىٰ إِبْرَاهِيمَ وَعَلَىٰ آلِ إِبْرَاهِيمَ إِنَّكَ حَمِيدٌ مَجِيدٌ
                    """,
                transliteration: """
                    Allāhumma ṣalli 'alā Muḥammadin wa 'alā āli Muḥammad, kamā ṣallayta 'alā Ibrāhīma wa 'alā āli Ibrāhīm, innaka Ḥamīdun Majīd.
                    Allāhumma bārik 'alā Muḥammadin wa 'alā āli Muḥammad, kamā bārakta 'alā Ibrāhīma wa 'alā āli Ibrāhīm, innaka Ḥamīdun Majīd.
                    """,
                translation: """
                    O Allah, send blessings upon Muhammad and upon the family of Muhammad, as You sent blessings upon Ibrahim and upon the family of Ibrahim. Indeed, You are Praiseworthy, Glorious.
                    O Allah, bless Muhammad and the family of Muhammad, as You blessed Ibrahim and the family of Ibrahim. Indeed, You are Praiseworthy, Glorious.
                    """,
                usedIn: "Final sitting",
                audioFileName: "recitation-durood"
            ),
            PrayerRecitation(
                id: "dua",
                name: "Du'ā' before Salām",
                arabicText: "رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ",
                transliteration: "Rabbanā ātinā fid-dunyā ḥasanatan wa fil-ākhirati ḥasanatan wa qinā 'adhāb an-nār.",
                translation: "Our Lord, give us good in this world and good in the Hereafter, and protect us from the punishment of the Fire.",
                usedIn: "Final sitting",
                audioFileName: "recitation-dua"
            ),
            PrayerRecitation(
                id: "qunut",
                name: "Qunūt (Witr Du'ā')",
                arabicText: """
                    اللَّهُمَّ إِنَّا نَسْتَعِينُكَ وَنَسْتَغْفِرُكَ وَنُؤْمِنُ بِكَ وَنَتَوَكَّلُ عَلَيْكَ وَنُثْنِي عَلَيْكَ الْخَيْرَ
                    نَشْكُرُكَ وَلَا نَكْفُرُكَ وَنَخْلَعُ وَنَتْرُكُ مَنْ يَفْجُرُكَ
                    اللَّهُمَّ إِيَّاكَ نَعْبُدُ وَلَكَ نُصَلِّي وَنَسْجُدُ وَإِلَيْكَ نَسْعَىٰ وَنَحْفِدُ
                    نَرْجُو رَحْمَتَكَ وَنَخْشَىٰ عَذَابَكَ إِنَّ عَذَابَكَ بِالْكُفَّارِ مُلْحِقٌ
                    """,
                transliteration: """
                    Allāhumma innā nasta'īnuka wa nastaghfiruka wa nu'minu bika wa natawakkalu 'alayka wa nuthnī 'alaykal-khayr.
                    Nashkuruka wa lā nakfuruka wa nakhla'u wa natruku man yafjuruk.
                    Allāhumma iyyāka na'budu wa laka nuṣallī wa nasjudu wa ilayka nas'ā wa naḥfid.
                    Narjū raḥmataka wa nakhshā 'adhābaka inna 'adhābaka bil-kuffāri mulḥiq.
                    """,
                translation: """
                    O Allah, we seek Your help and Your forgiveness, and we believe in You and rely upon You, and we praise You with all good.
                    We thank You and we are not ungrateful to You, and we abandon and leave whoever disobeys You.
                    O Allah, You alone we worship, and to You we pray and prostrate, and toward You we hasten and serve.
                    We hope for Your mercy and fear Your punishment. Indeed, Your punishment overtakes the disbelievers.
                    """,
                usedIn: "Witr 3rd rak'ah only",
                audioFileName: "recitation-qunut"
            ),
        ]
    }

    // MARK: - Short Surahs

    static func shortSurahs() -> [ShortSurah] {
        [
            ShortSurah(
                id: 114,
                name: "An-Nās",
                arabicName: "النَّاس",
                verseCount: 6,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    قُلْ أَعُوذُ بِرَبِّ النَّاسِ · مَلِكِ النَّاسِ · إِلَٰهِ النَّاسِ · مِنْ شَرِّ الْوَسْوَاسِ الْخَنَّاسِ · الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ · مِنَ الْجِنَّةِ وَالنَّاسِ
                    """,
                transliteration: "Qul a'ūdhu bi Rabbin-nās. Malikinnās. Ilāhin-nās. Min sharril-waswāsil-khannās. Alladhī yuwaswisu fī ṣudūrin-nās. Minal-jinnati wan-nās.",
                translation: "Say: I seek refuge in the Lord of mankind, the King of mankind, the God of mankind, from the evil of the retreating whisperer, who whispers in the hearts of mankind, from among the jinn and mankind.",
                audioFileName: "surah-114"
            ),
            ShortSurah(
                id: 113,
                name: "Al-Falaq",
                arabicName: "الفَلَق",
                verseCount: 5,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ · مِنْ شَرِّ مَا خَلَقَ · وَمِنْ شَرِّ غَاسِقٍ إِذَا وَقَبَ · وَمِنْ شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ · وَمِنْ شَرِّ حَاسِدٍ إِذَا حَسَدَ
                    """,
                transliteration: "Qul a'ūdhu bi Rabbil-falaq. Min sharri mā khalaq. Wa min sharri ghāsiqin idhā waqab. Wa min sharrin-naffāthāti fil-'uqad. Wa min sharri ḥāsidin idhā ḥasad.",
                translation: "Say: I seek refuge in the Lord of the daybreak, from the evil of what He has created, from the evil of darkness when it settles, from the evil of those who blow on knots, and from the evil of an envier when he envies.",
                audioFileName: "surah-113"
            ),
            ShortSurah(
                id: 112,
                name: "Al-Ikhlāṣ",
                arabicName: "الإخلاص",
                verseCount: 4,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    قُلْ هُوَ اللَّهُ أَحَدٌ · اللَّهُ الصَّمَدُ · لَمْ يَلِدْ وَلَمْ يُولَدْ · وَلَمْ يَكُنْ لَهُ كُفُوًا أَحَدٌ
                    """,
                transliteration: "Qul Huw-Allāhu Aḥad. Allāhuṣ-Ṣamad. Lam yalid wa lam yūlad. Wa lam yakun lahū kufuwan aḥad.",
                translation: "Say: He is Allah, the One. Allah, the Eternal Refuge. He neither begets nor is born, nor is there any equivalent to Him.",
                audioFileName: "surah-112"
            ),
            ShortSurah(
                id: 111,
                name: "Al-Masad",
                arabicName: "المَسَد",
                verseCount: 5,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    تَبَّتْ يَدَا أَبِي لَهَبٍ وَتَبَّ · مَا أَغْنَىٰ عَنْهُ مَالُهُ وَمَا كَسَبَ · سَيَصْلَىٰ نَارًا ذَاتَ لَهَبٍ · وَامْرَأَتُهُ حَمَّالَةَ الْحَطَبِ · فِي جِيدِهَا حَبْلٌ مِنْ مَسَدٍ
                    """,
                transliteration: "Tabbat yadā Abī Lahabin wa tabb. Mā aghnā 'anhu māluhū wa mā kasab. Sayaṣlā nāran dhāta lahab. Wam-ra'atuhū ḥammālatal-ḥaṭab. Fī jīdihā ḥablun min masad.",
                translation: "May the hands of Abu Lahab be ruined, and ruined is he. His wealth will not avail him or that which he gained. He will burn in a Fire of blazing flame. And his wife — the carrier of firewood. Around her neck is a rope of palm fiber.",
                audioFileName: "surah-111"
            ),
            ShortSurah(
                id: 110,
                name: "An-Naṣr",
                arabicName: "النَّصر",
                verseCount: 3,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    إِذَا جَاءَ نَصْرُ اللَّهِ وَالْفَتْحُ · وَرَأَيْتَ النَّاسَ يَدْخُلُونَ فِي دِينِ اللَّهِ أَفْوَاجًا · فَسَبِّحْ بِحَمْدِ رَبِّكَ وَاسْتَغْفِرْهُ إِنَّهُ كَانَ تَوَّابًا
                    """,
                transliteration: "Idhā jā'a naṣrullāhi wal-fatḥ. Wa ra'aytan-nāsa yadkhulūna fī dīnillāhi afwājā. Fa sabbiḥ bi ḥamdi Rabbika wastaghfirh, innahū kāna tawwābā.",
                translation: "When the victory of Allah has come and the conquest, and you see the people entering into the religion of Allah in multitudes, then exalt with praise of your Lord and ask His forgiveness. Indeed, He is ever accepting of repentance.",
                audioFileName: "surah-110"
            ),
            ShortSurah(
                id: 109,
                name: "Al-Kāfirūn",
                arabicName: "الكافرون",
                verseCount: 6,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    قُلْ يَا أَيُّهَا الْكَافِرُونَ · لَا أَعْبُدُ مَا تَعْبُدُونَ · وَلَا أَنْتُمْ عَابِدُونَ مَا أَعْبُدُ · وَلَا أَنَا عَابِدٌ مَا عَبَدْتُمْ · وَلَا أَنْتُمْ عَابِدُونَ مَا أَعْبُدُ · لَكُمْ دِينُكُمْ وَلِيَ دِينِ
                    """,
                transliteration: "Qul yā ayyuhal-kāfirūn. Lā a'budu mā ta'budūn. Wa lā antum 'ābidūna mā a'bud. Wa lā ana 'ābidum mā 'abadtum. Wa lā antum 'ābidūna mā a'bud. Lakum dīnukum wa liya dīn.",
                translation: "Say: O disbelievers, I do not worship what you worship, nor are you worshippers of what I worship. Nor will I be a worshipper of what you worship, nor will you be worshippers of what I worship. For you is your religion, and for me is my religion.",
                audioFileName: "surah-109"
            ),
            ShortSurah(
                id: 108,
                name: "Al-Kawthar",
                arabicName: "الكَوثَر",
                verseCount: 3,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ · فَصَلِّ لِرَبِّكَ وَانْحَرْ · إِنَّ شَانِئَكَ هُوَ الْأَبْتَرُ
                    """,
                transliteration: "Innā a'ṭaynākal-kawthar. Fa ṣalli li Rabbika wanḥar. Inna shāni'aka huwal-abtar.",
                translation: "Indeed, We have granted you al-Kawthar (abundance). So pray to your Lord and sacrifice. Indeed, your enemy is the one cut off.",
                audioFileName: "surah-108"
            ),
            ShortSurah(
                id: 107,
                name: "Al-Mā'ūn",
                arabicName: "الماعون",
                verseCount: 7,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    أَرَأَيْتَ الَّذِي يُكَذِّبُ بِالدِّينِ · فَذَٰلِكَ الَّذِي يَدُعُّ الْيَتِيمَ · وَلَا يَحُضُّ عَلَىٰ طَعَامِ الْمِسْكِينِ · فَوَيْلٌ لِلْمُصَلِّينَ · الَّذِينَ هُمْ عَنْ صَلَاتِهِمْ سَاهُونَ · الَّذِينَ هُمْ يُرَاءُونَ · وَيَمْنَعُونَ الْمَاعُونَ
                    """,
                transliteration: "Ara'aytal-ladhī yukadhdhibu bid-dīn. Fadhālikal-ladhī yadu''ul-yatīm. Wa lā yaḥuḍḍu 'alā ṭa'āmil-miskīn. Fa waylul-lil-muṣallīn. Alladhīna hum 'an ṣalātihim sāhūn. Alladhīna hum yurā'ūn. Wa yamna'ūnal-mā'ūn.",
                translation: "Have you seen the one who denies the Recompense? For that is the one who drives away the orphan, and does not encourage the feeding of the poor. So woe to those who pray but are heedless of their prayer — those who make show of their deeds and withhold small kindnesses.",
                audioFileName: "surah-107"
            ),
            ShortSurah(
                id: 106,
                name: "Quraysh",
                arabicName: "قُرَيش",
                verseCount: 4,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    لِإِيلَافِ قُرَيْشٍ · إِيلَافِهِمْ رِحْلَةَ الشِّتَاءِ وَالصَّيْفِ · فَلْيَعْبُدُوا رَبَّ هَٰذَا الْبَيْتِ · الَّذِي أَطْعَمَهُمْ مِنْ جُوعٍ وَآمَنَهُمْ مِنْ خَوْفٍ
                    """,
                transliteration: "Li- īlāfi Quraysh. Īlāfihim riḥlatash-shitā'i waṣ-ṣayf. Fal-ya'budū Rabba hādhal-bayt. Alladhī aṭ'amahum min jū'in wa āmanahum min khawf.",
                translation: "For the accustomed security of the Quraysh — their accustomed security in the caravan of winter and summer — let them worship the Lord of this House, who has fed them against hunger and made them safe from fear.",
                audioFileName: "surah-106"
            ),
            ShortSurah(
                id: 105,
                name: "Al-Fīl",
                arabicName: "الفيل",
                verseCount: 5,
                arabicText: """
                    بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
                    أَلَمْ تَرَ كَيْفَ فَعَلَ رَبُّكَ بِأَصْحَابِ الْفِيلِ · أَلَمْ يَجْعَلْ كَيْدَهُمْ فِي تَضْلِيلٍ · وَأَرْسَلَ عَلَيْهِمْ طَيْرًا أَبَابِيلَ · تَرْمِيهِمْ بِحِجَارَةٍ مِنْ سِجِّيلٍ · فَجَعَلَهُمْ كَعَصْفٍ مَأْكُولٍ
                    """,
                transliteration: "Alam tara kayfa fa'ala Rabbuka bi-aṣḥābil-fīl. Alam yaj'al kaydahum fī taḍlīl. Wa arsala 'alayhim ṭayran abābīl. Tarmīhim bi ḥijāratim min sijjīl. Faja'alahum ka'aṣfim ma'kūl.",
                translation: "Have you not considered how your Lord dealt with the companions of the elephant? Did He not make their plan into misguidance? And He sent against them birds in flocks, striking them with stones of hard clay, and He made them like eaten straw.",
                audioFileName: "surah-105"
            ),
        ]
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
