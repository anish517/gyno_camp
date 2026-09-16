/// Nepal Administrative Geography — 7 Provinces → 77 Districts → Palikas (Municipalities / Rural Municipalities)
class NepalGeodata {
  static const Map<String, List<String>> districtsByProvince = {
    'Koshi': [
      'Taplejung', 'Panchthar', 'Ilam', 'Jhapa', 'Morang', 'Sunsari', 'Dhankuta', 'Terhathum', 'Sankhuwasabha', 'Bhojpur', 'Solukhumbu', 'Okhaldhunga', 'Khotang', 'Udayapur',
    ],
    'Madhesh': [
      'Saptari', 'Siraha', 'Dhanusha', 'Mahottari', 'Sarlahi', 'Rautahat', 'Bara', 'Parsa',
    ],
    'Bagmati': [
      'Sindhuli', 'Ramechhap', 'Dolakha', 'Sindhupalchok', 'Kavrepalanchok', 'Lalitpur', 'Bhaktapur', 'Kathmandu', 'Nuwakot', 'Rasuwa', 'Dhading', 'Makwanpur', 'Chitwan',
    ],
    'Gandaki': [
      'Gorkha', 'Manang', 'Mustang', 'Myagdi', 'Kaski', 'Lamjung', 'Tanahu', 'Nawalpur', 'Syangja', 'Parbat', 'Baglung',
    ],
    'Lumbini': [
      'Gulmi', 'Palpa', 'Nawalparasi (East)', 'Rupandehi', 'Kapilvastu', 'Arghakhanchi', 'Pyuthan', 'Rolpa', 'East Rukum', 'Dang', 'Banke', 'Bardiya',
    ],
    'Karnali': [
      'Dolpa', 'Mugu', 'Humla', 'Jumla', 'Kalikot', 'Dailekh', 'Jajarkot', 'West Rukum', 'Salyan', 'Surkhet',
    ],
    'Sudurpashchim': [
      'Bajura', 'Bajhang', 'Achham', 'Doti', 'Dadeldhura', 'Baitadi', 'Darchula', 'Kanchanpur', 'Kailali',
    ],
  };

  static const Map<String, List<String>> palikasByDistrict = {
    'Bhojpur': [
      'Bhojpur', 'Shadananda', 'Aamchok', 'Arun', 'Hatuwagadhi', 'Pauwadungma',
      'Ramprasad Rai', 'Salpasilichho', 'Tyamke Maiyunm',
    ],
    'Dhankuta': [
      'Dhankuta', 'Mahalaxmi', 'Pakhribas', 'Chaubise', 'Chhathar Jorpati', 'Sahidbhumi',
      'Sangurigadhi',
    ],
    'Ilam': [
      'Deumai', 'Ilam', 'Mai', 'Suryodaya', 'Chulachuli', 'Fakphokthum', 'Maijogmai',
      'Mangsebung', 'Rong', 'Sandakpur',
    ],
    'Jhapa': [
      'Arjundhara', 'Bhadrapur', 'Birtamod', 'Damak', 'Gauradaha', 'Kankai',
      'Mechinagar', 'Shivasatakshi', 'Barhadashi', 'Buddhashanti', 'Gauriganj',
      'Haldibari', 'Jhapa', 'Kachankawal', 'Kamal',
    ],
    'Khotang': [
      'Diktel Rupakot Majhuwagadhi', 'Halesi Tuwachung', 'Ainselukhark', 'Barahapokhari',
      'Diprung Chuichumma', 'Jantedhunga', 'Kepilasgadhi', 'Khotehang', 'Rawabesi',
      'Sakela',
    ],
    'Morang': [
      'Belbari', 'Biratnagar Metropolitan City', 'Letang', 'Pathari Sanischare',
      'Rangeli', 'Ratuwamai', 'Sundarharaicha', 'Sunbarshi', 'Urlabari', 'Budhiganga',
      'Dhanpalthan', 'Gramthan', 'Jahada', 'Kanepokhari', 'Katahari', 'Kerabari',
      'Miklajung',
    ],
    'Okhaldhunga': [
      'Siddhicharan', 'Champadevi', 'Chisankhugadhi', 'Khijidemba', 'Likhu',
      'Manebhanjyang', 'Molung', 'Sunkoshi',
    ],
    'Panchthar': [
      'Fidim', 'Falelung', 'Falgunanda', 'Hilihang', 'Kummayak', 'Miklajung', 'Tumbewa',
      'Yangwarak',
    ],
    'Sankhuwasabha': [
      'Chainpur', 'Dharmadevi', 'Khandbari', 'Madi', 'Panchakhapan', 'Bhotkhola',
      'Chichila', 'Makalu', 'Sabha Pokhari', 'Silichong',
    ],
    'Solukhumbu': [
      'Solududhkunda', 'Dudhkoshi', 'Dudhkaushika', 'Khumbu Pasanglhamu', 'Likhu Pike',
      'Mahakulung', 'Nechasalyan', 'Sotang',
    ],
    'Sunsari': [
      'Barahakshetra', 'Dharan Sub-Metropolitan', 'Duhabi', 'Inaruwa',
      'Itahari Sub-Metropolitan', 'Ramdhuni', 'Barju', 'Bhokraha Narasimha', 'Dewanganj',
      'Gadhi', 'Harinagar', 'Koshi',
    ],
    'Taplejung': [
      'Fungling', 'Aathrai Triveni', 'Faktanglung', 'Maiwakhola', 'Meringden',
      'Mikwakhola', 'Sidingwa', 'Sirijangha', 'Yangwarak',
    ],
    'Terhathum': [
      'Laligurans', 'Myanglung', 'Aathrai', 'Chhathar', 'Menchayayem', 'Phedap',
    ],
    'Udayapur': [
      'Belaka', 'Chaudandigadhi', 'Katari', 'Triyuga', 'Rautamai', 'Sunkoshi', 'Tapli',
      'Udayapurgadhi',
    ],
    'Bara': [
      'Jitpur Simara Sub-Metropolitan', 'Kalaiya Sub-Metropolitan', 'Kolhabi',
      'Mahagadhimai', 'Nijgadh', 'Simraungadh', 'Adarsh Kotwal', 'Baragadhi',
      'Bishrampur', 'Devtal', 'Feta', 'Karaiyamai', 'Pacharauta', 'Parwanipur',
      'Prasuni', 'Suwarna',
    ],
    'Dhanusha': [
      'Chhireshwarnath', 'Dhanusadham', 'Ganeshman Charnath', 'Hansapur',
      'Janakpurdham Sub-Metropolitan', 'Kamala', 'Mithila', 'Mithila Bihari', 'Nagarain',
      'Sabaila', 'Sahidnagar', 'Bideha', 'Aurahi', 'Bateshwar', 'Dhanauji',
      'Janaknandani', 'Lakshminiya', 'Mukhiyapatti Musaharniya',
    ],
    'Mahottari': [
      'Aurahi', 'Balawa', 'Bardibas', 'Bhangaha', 'Gaushala', 'Jaleshwor', 'Loharpatti',
      'Manara Shiswa', 'Matihani', 'Ramgopalpur', 'Ekdara', 'Mahottari', 'Pipara',
      'Samsi', 'Sonama',
    ],
    'Parsa': [
      'Bahudarmai', 'Birgunj Metropolitan City', 'Parsagadhi', 'Pokhariya',
      'Bindabasini', 'Chhipaharmai', 'Dhobini', 'Jagarnathpur', 'Jirabhawani',
      'Kalikamai', 'Pakahamainpur', 'Paterwa Sugauli', 'Sakhuwa Prasauni', 'Thori',
    ],
    'Rautahat': [
      'Baudhimai', 'Brindaban', 'Chandrapur', 'Dewahi Gonahi', 'Gadhimai', 'Garuda',
      'Gaur', 'Gujara', 'Ishanath', 'Katahariya', 'Madhav Narayan', 'Maulapur', 'Paroha',
      'Phatuwa Bijaypur', 'Rajdevi', 'Rajpur', 'Durga Bhagawati', 'Yamunamai',
    ],
    'Saptari': [
      'Bodebarsain', 'Dakneshwari', 'Hanumannagar Kankalini', 'Kanchanrup', 'Khadak',
      'Rajbiraj', 'Sambhunath', 'Saptakoshi', 'Surunga', 'Agnisair Krishna Savaran',
      'Balan-Bihul', 'Bishnupur', 'Chhinnamasta', 'Mahadeva', 'Rupani',
      'Tilathi Koiladi', 'Tirahut', 'Belhi Chapena',
    ],
    'Sarlahi': [
      'Bagmati', 'Balara', 'Barahathawa', 'Godaita', 'Haripur', 'Haripurwa', 'Hariwan',
      'Ishworpur', 'Kabilasi', 'Lalbandi', 'Malangwa', 'Basbariya', 'Bishnu',
      'Brahmapuri', 'Chakraghatta', 'Chandranagar', 'Dhankaul', 'Kaudena', 'Parsa',
      'Ramnagar',
    ],
    'Siraha': [
      'Dhangadhimai', 'Golbazar', 'Kalyanpur', 'Karjanha', 'Lahan', 'Mirchaiya',
      'Siraha', 'Sukhipur', 'Arnama', 'Aurahi', 'Bariyarpatti', 'Bhagwanpur',
      'Bishnupur', 'Laxmipur Patari', 'Naraha', 'Navarajpur', 'Sakhuwanankarkatti',
    ],
    'Bhaktapur': [
      'Bhaktapur', 'Changunarayan', 'Madhyapur Thimi', 'Suryabinayak',
    ],
    'Chitwan': [
      'Bharatpur Metropolitan City', 'Kalika', 'Khairahani', 'Madi', 'Rapti',
      'Ratnanagar', 'Ichhyakamana',
    ],
    'Dhading': [
      'Dhunibeshi', 'Nilkantha', 'Benighat Rorang', 'Gajuri', 'Galchhi', 'Gangajamuna',
      'Jwalamukhi', 'Khaniyabas', 'Netrawati Dabjong', 'Rubee Valley', 'Siddhalek',
      'Thakre', 'Tripura Sundari',
    ],
    'Dolakha': [
      'Bhimeshwar', 'Jiri', 'Baiteswor', 'Bigu', 'Gaurishankar', 'Kalinchok', 'Melung',
      'Sailung', 'Tamakoshi',
    ],
    'Kathmandu': [
      'Budhanilkantha', 'Chandragiri', 'Dakshinkali', 'Gokarneshwor',
      'Kageshwari Manohara', 'Kathmandu Metropolitan City', 'Kirtipur', 'Nagarjun',
      'Shankharapur', 'Tarakeshwor', 'Tokha',
    ],
    'Kavrepalanchok': [
      'Banepa', 'Dhulikhel', 'Mandandeupur', 'Namobuddha', 'Panauti', 'Panchkhal',
      'Bethanchowk', 'Bhumlu', 'Chaurideurali', 'Khanikhola', 'Mahabharat', 'Roshi',
      'Temal',
    ],
    'Lalitpur': [
      'Godawari', 'Lalitpur Metropolitan City', 'Mahalaxmi', 'Bagmati', 'Konjyosom',
      'Mahankal',
    ],
    'Makwanpur': [
      'Hetauda Sub-Metropolitan', 'Thaha', 'Bagmati', 'Bakaiya', 'Bhimphedi',
      'Indrasarowar', 'Kailash', 'Makawanpurgadhi', 'Manahari', 'Raksirang',
    ],
    'Nuwakot': [
      'Belkotgadhi', 'Bidur', 'Dupcheshwar', 'Kakani', 'Kispang', 'Likhu', 'Myagang',
      'Panchakanya', 'Shivapuri', 'Suryagadhi', 'Tadi', 'Tarkeshwar',
    ],
    'Ramechhap': [
      'Manthali', 'Ramechhap', 'Doramba Sailung', 'Gokulganga', 'Khandadevi',
      'Likhu Tamakoshi', 'Sunapati', 'Umakunda',
    ],
    'Rasuwa': [
      'Gosaikunda', 'Kalika', 'Naukunda', 'Parbatikunda', 'Uttargaya',
    ],
    'Sindhuli': [
      'Dudhauli', 'Kamalamai', 'Fikkal', 'Ghyanglekh', 'Golanjor', 'Hariharpurgadhi',
      'Marin', 'Sunkoshi', 'Tinpatan',
    ],
    'Sindhupalchok': [
      'Barhabise', 'Chautara Sangachokgadhi', 'Melamchi', 'Balefi', 'Bhotekoshi',
      'Helambu', 'Indrawati', 'Jugal', 'Lisankhu Pakhar', 'Panchpokhari Thangpal',
      'Sunkoshi', 'Tripurasundari',
    ],
    'Baglung': [
      'Baglung', 'Dhorpatan', 'Galkot', 'Jaimini', 'Badigad', 'Bareng', 'Kathekhola',
      'Nisikhola', 'Tamankhola', 'Tarakhola',
    ],
    'Gorkha': [
      'Gorkha', 'Palungtar', 'Aarughat', 'Ajirkot', 'Bhimsen Thapa', 'Chumnubri',
      'Dharche', 'Gandaki', 'Sahid Lakhan', 'Siranchok', 'Barpak Sulikot',
    ],
    'Kaski': [
      'Pokhara Metropolitan City', 'Annapurna', 'Machhapuchhre', 'Madi', 'Rupa',
    ],
    'Lamjung': [
      'Besisahar', 'Madhya Nepal', 'Rainas', 'Sundarbazar', 'Dordi', 'Dudhpokhari',
      'Kwhlosothar', 'Marsyangdi',
    ],
    'Manang': [
      'Chame', 'Disyang', 'Narpa Bhumi', 'Nason',
    ],
    'Mustang': [
      'Baragung Muktikshetra', 'Gharpajhong', 'Lomanthang', 'Thasang', 'Dalome',
    ],
    'Myagdi': [
      'Beni', 'Annapurna', 'Dhaulagiri', 'Malika', 'Mangala', 'Raghuganga',
    ],
    'Nawalpur': [
      'Devchuli', 'Gaindakot', 'Kawasoti', 'Madhyabindu', 'Baidikali', 'Binayi Tribeni',
      'Bulingtar', 'Hupsekot',
    ],
    'Parbat': [
      'Kushma', 'Phalewas', 'Bihadi', 'Jaljala', 'Mahashila', 'Modi', 'Paiyun',
    ],
    'Syangja': [
      'Chapakot', 'Galyang', 'Putalibazar', 'Waling', 'Andhikhola', 'Arjun Chaupari',
      'Biruwa', 'Fedikhola', 'Harinas', 'Kaligandaki', 'Bhirkot',
    ],
    'Tanahu': [
      'Bhanu', 'Bhimad', 'Byas', 'Shuklagandaki', 'Anbukhaireni', 'Bandipur', 'Devghat',
      'Ghiring', 'Myagde', 'Rishing',
    ],
    'Arghakhanchi': [
      'Bhumikasthan', 'Sandhikharka', 'Sitganga', 'Chhatradev', 'Malarani', 'Panini',
    ],
    'Banke': [
      'Kohalpur', 'Nepalgunj Sub-Metropolitan', 'Baijanath', 'Duduwa', 'Janaki',
      'Khajura', 'Narainapur', 'Rapti Sonari',
    ],
    'Bardiya': [
      'Bansgadhi', 'Barbardiya', 'Gulariya', 'Madhuwan', 'Rajapur', 'Thakurbaba',
      'Badhaiyatal', 'Geruwa',
    ],
    'Dang': [
      'Ghorahi Sub-Metropolitan', 'Lamahi', 'Tulsipur Sub-Metropolitan', 'Babai',
      'Bangalachuli', 'Dangisharan', 'Gadhawa', 'Rajpur', 'Rapti', 'Shantinagar',
    ],
    'East Rukum': [
      'Bhume', 'Putha Uttarganga', 'Sisne',
    ],
    'Gulmi': [
      'Musikot', 'Resunga', 'Chandrakot', 'Chhatrakot', 'Dhurkot', 'Gulmidarbar', 'Isma',
      'Kaligandaki', 'Madane', 'Malika', 'Ruru', 'Satyawati',
    ],
    'Kapilvastu': [
      'Banganga', 'Buddhabhumi', 'Kapilvastu', 'Krishnanagar', 'Maharajgunj', 'Shivaraj',
      'Bijayanagar', 'Mayadevi', 'Suddhodhan', 'Yasodhara',
    ],
    'Nawalparasi (East)': [
      'Bardaghat', 'Ramgram', 'Sunwal', 'Palhinandan', 'Pratappur', 'Sarawal', 'Susta',
    ],
    'Palpa': [
      'Rampur', 'Tansen', 'Bagnaskali', 'Mathagadhi', 'Nisdi', 'Purbakhola',
      'Rainadevi Chhahara', 'Rambha', 'Ribdikot', 'Tinau',
    ],
    'Pyuthan': [
      'Pyuthan', 'Swargadwari', 'Gaumukhi', 'Jhimruk', 'Mallarani', 'Mandavi',
      'Naubahini', 'Sarumarani', 'Airawati',
    ],
    'Rolpa': [
      'Rolpa', 'Duikholi', 'Gangadev', 'Lungri', 'Madi', 'Runtigadhi', 'Sukidaha',
      'Sunchhahari', 'Suribang', 'Thabang',
    ],
    'Rupandehi': [
      'Butwal Sub-Metropolitan', 'Devdaha', 'Lumbini Sanskritik', 'Sainamaina',
      'Siddharthanagar', 'Tilottama', 'Gaidahawa', 'Kanchan', 'Kotahimai', 'Marchawari',
      'Mayadevi', 'Omsatiya', 'Rohini', 'Sammarimai', 'Siyari', 'Suddhodhan',
    ],
    'Dailekh': [
      'Aathbis', 'Chamunda Bindrasaini', 'Dullu', 'Narayan', 'Bhagawatimai', 'Bhairabi',
      'Dungeshwar', 'Gurans', 'Mahabu', 'Naumule', 'Thantikandh',
    ],
    'Dolpa': [
      'Thuli Bheri', 'Tripura Sundari', 'Chharka Tangsong', 'Dolpo Buddha', 'Jagadulla',
      'Kaike', 'Mudkechula', 'Shey Phoksundo',
    ],
    'Humla': [
      'Adanchuli', 'Chankheli', 'Kharpunath', 'Namkha', 'Sarkegad', 'Simkot', 'Tanjakot',
    ],
    'Jajarkot': [
      'Bhedabari', 'Chhedagad', 'Nalgad', 'Barekot', 'Junichande', 'Kuse', 'Shivalaya',
    ],
    'Jumla': [
      'Chandannath', 'Guthichaur', 'Hima', 'Kanakasundari', 'Patarasi', 'Sinja',
      'Tatopani', 'Tila',
    ],
    'Kalikot': [
      'Khandachakra', 'Raskot', 'Tilagufa', 'Mahawai', 'Narharinath', 'Pachaljharana',
      'Palata', 'Sanni Triveni', 'Shubha Kalika',
    ],
    'Mugu': [
      'Chhayanath Rara', 'Khatyad', 'Mugum Karmarong', 'Soru',
    ],
    'Salyan': [
      'Bagchaur', 'Bangad Kupinde', 'Sharada', 'Chhatreshwari', 'Darma', 'Dhorchaur',
      'Kalimati', 'Kapurkot', 'Kumakh', 'Tribeni',
    ],
    'Surkhet': [
      'Bheriganga', 'Birendranagar', 'Gurbhakot', 'Lekbeshi', 'Panchapuri', 'Barahatal',
      'Chaukune', 'Chingad', 'Simta',
    ],
    'West Rukum': [
      'Aathbiskot', 'Chaurjahari', 'Musikot', 'Banfikot', 'Sani Bheri', 'Tribeni',
    ],
    'Achham': [
      'Kamalbazar', 'Mangalsen', 'Panchadewal Binayak', 'Sanfebagar',
      'Bannigadhi Jayagadh', 'Chaurpati', 'Dhakari', 'Mellekh', 'Ramaroshan',
      'Turmakhand',
    ],
    'Baitadi': [
      'Dasharathchand', 'Melauli', 'Patan', 'Purchaudi', 'Dilasaini', 'Dogadakedar',
      'Pancheshwar', 'Purnachandi', 'Shivanath', 'Sigas', 'Surnaya',
    ],
    'Bajhang': [
      'Bungal', 'Jayaprithvi', 'Bithadchir', 'Chhabispathibhera', 'Durgathali',
      'Kedarsyu', 'Khaptadchhanna', 'Masta', 'Saipal', 'Surma', 'Talkot', 'Thalara',
    ],
    'Bajura': [
      'Badimalika', 'Budhinanda', 'Budhiganga', 'Gaumul', 'Himali', 'Jagannath',
      'Khaptad Chhededaha', 'Swamikartik Khapar', 'Tribeni',
    ],
    'Dadeldhura': [
      'Amargadhi', 'Parshuram', 'Ajaymeru', 'Alital', 'Bhagawatikot', 'Ganyapdhura',
      'Navadurga',
    ],
    'Darchula': [
      'Mahakali', 'Shailyashikhar', 'Apihimal', 'Byas', 'Dunhu', 'Lekam', 'Malikarjun',
      'Marma', 'Naugad',
    ],
    'Doti': [
      'Dipayal Silgadhi', 'Shikhar', 'Adharsh', 'Badikedar', 'Bogatan Funsil', 'Jorayal',
      'K.I. Singh', 'Purbichauki', 'Sayal',
    ],
    'Kailali': [
      'Bhajani', 'Dhangadhi Sub-Metropolitan', 'Gauriganga', 'Ghodaghodi', 'Godawari',
      'Lamki Chuha', 'Tikapur', 'Bardgoriya', 'Chure', 'Janaki', 'Joshipur', 'Kailari',
      'Mohanyal',
    ],
    'Kanchanpur': [
      'Bedkot', 'Belauri', 'Bhimdatta', 'Krishnapur', 'Mahakali', 'Punarbas',
      'Shuklaphanta', 'Beldandi', 'Laljhadi',
    ],
  };

  static List<String> districtsFor(String? province) {
    if (province == null || province.isEmpty || province == 'all') {
      return districtsByProvince.values.expand((d) => d).toList()..sort();
    }
    return districtsByProvince[province] ?? [];
  }

  static List<String> get allDistricts =>
      districtsByProvince.values.expand((d) => d).toList()..sort();

  static String provinceOf(String? district) {
    if (district == null || district.trim().isEmpty) return 'Bagmati';
    final target = district.trim().toLowerCase();
    for (final entry in districtsByProvince.entries) {
      if (entry.value.any((d) => d.toLowerCase() == target)) {
        return entry.key;
      }
    }
    return 'Bagmati';
  }

  /// Returns sorted Palikas for the given district, optionally including extra / custom palikas
  static List<String> palikasFor(String? district, {List<String>? extraPalikas}) {
    final set = <String>{};
    if (district == null || district.trim().isEmpty || district == 'all') {
      for (final list in palikasByDistrict.values) {
        set.addAll(list);
      }
    } else {
      final key = palikasByDistrict.keys.firstWhere(
        (k) => k.toLowerCase() == district.trim().toLowerCase(),
        orElse: () => '',
      );
      if (key.isNotEmpty) {
        set.addAll(palikasByDistrict[key]!);
      }
    }
    if (extraPalikas != null) {
      for (final p in extraPalikas) {
        if (p.trim().isNotEmpty) set.add(p.trim());
      }
    }
    final sorted = set.toList()..sort();
    return sorted.isNotEmpty ? sorted : ['Palika Center', 'Ward 01', 'Ward 02', 'Ward 03'];
  }

  static List<String> get allPalikas =>
      palikasByDistrict.values.expand((p) => p).toSet().toList()..sort();
}
