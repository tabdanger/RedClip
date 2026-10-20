// Original Red Clip factory presets: instrument banks and producer-style packs.
// Made for Red Clip's own controls (no other product's presets were copied).
// Keep the order stable: hosts may remember a factory preset by its number.

extension Preset {
    static let factory: [Preset] = [
        // Essentials
        Preset(bank: "Essentials", name: "Default", values: [:]),
        Preset(bank: "Essentials", name: "Gentle Master", values: [.inputDB: 2, .clipMode: 1, .oversampling: 2, .gold: 25, .alchemy: 30, .boxTone: 1]),
        Preset(bank: "Essentials", name: "Loud Master", values: [.inputDB: 3, .driveDB: 4, .oversampling: 2, .gold: 55, .goldMode: 1, .alchemy: 50, .boxTone: 2]),
        Preset(bank: "Essentials", name: "Drum Bus Smash", values: [.driveDB: 9, .ceilingDB: -1.0, .mix: 70, .clipMode: 0, .oversampling: 2, .gold: 70, .goldMode: 1, .unity: 1, .alchemy: 20]),
        Preset(bank: "Essentials", name: "808 Edge", values: [.driveDB: 7, .oversampling: 2, .gold: 35, .unity: 1, .alchemy: 65]),
        Preset(bank: "Essentials", name: "Transient Shave", values: [.inputDB: 3, .ceilingDB: -1.0, .clipMode: 1, .oversampling: 2, .unity: 1, .alchemy: 40]),
        // Mix Bus & Master
        Preset(bank: "Mix Bus & Master", name: "Clean Peak Catch", values: [.driveDB: 1, .clipMode: 1, .oversampling: 2, .alchemy: 15]),
        Preset(bank: "Mix Bus & Master", name: "Streaming Ready", values: [.inputDB: 2, .driveDB: 2, .ceilingDB: -1.0, .clipMode: 1, .oversampling: 2, .gold: 30, .alchemy: 35, .boxTone: 1]),
        Preset(bank: "Mix Bus & Master", name: "Club Loud", values: [.inputDB: 4, .driveDB: 5, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 55, .boxTone: 2]),
        Preset(bank: "Mix Bus & Master", name: "Analog Glue Bus", values: [.inputDB: 1, .driveDB: 3, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 40, .goldMode: 1, .unity: 1, .alchemy: 30, .boxTone: 2]),
        Preset(bank: "Mix Bus & Master", name: "Transparent +2", values: [.inputDB: 2, .clipMode: 1, .oversampling: 2, .gold: 20, .alchemy: 20]),
        Preset(bank: "Mix Bus & Master", name: "Dense Modern Master", values: [.inputDB: 3, .driveDB: 4, .oversampling: 2, .gold: 70, .alchemy: 45, .boxTone: 1]),
        Preset(bank: "Mix Bus & Master", name: "Vintage Converter", values: [.inputDB: 1, .driveDB: 2, .clipMode: 1, .oversampling: 2, .gold: 50, .goldMode: 1, .alchemy: 60, .boxTone: 2]),
        Preset(bank: "Mix Bus & Master", name: "Mix Bus Parallel", values: [.driveDB: 8, .ceilingDB: -0.5, .mix: 40, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 30]),
        // Drums
        Preset(bank: "Drums", name: "Kick Punch", values: [.driveDB: 6, .ceilingDB: -1.0, .outputDB: 1.0, .clipMode: 0, .oversampling: 2, .gold: 20, .unity: 1, .alchemy: 10]),
        Preset(bank: "Drums", name: "Kick Sub Tame", values: [.driveDB: 4, .ceilingDB: -0.5, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .alchemy: 25]),
        Preset(bank: "Drums", name: "Snare Crack", values: [.driveDB: 8, .ceilingDB: -1.5, .outputDB: 1.5, .clipMode: 0, .oversampling: 2, .gold: 30, .goldMode: 1, .unity: 1, .alchemy: 20]),
        Preset(bank: "Drums", name: "Snare Body", values: [.driveDB: 5, .ceilingDB: -1.0, .outputDB: 1.0, .oversampling: 2, .gold: 55, .goldMode: 1, .alchemy: 35, .boxTone: 2]),
        Preset(bank: "Drums", name: "Clap Snap", values: [.driveDB: 7, .ceilingDB: -1.0, .outputDB: 1.0, .clipMode: 0, .oversampling: 2, .gold: 25, .unity: 1, .alchemy: 30]),
        Preset(bank: "Drums", name: "Hats Tame", values: [.driveDB: 3, .ceilingDB: -2.0, .outputDB: 2.0, .clipMode: 1, .oversampling: 2, .alchemy: 70, .boxTone: 2]),
        Preset(bank: "Drums", name: "Perc Bite", values: [.driveDB: 6, .ceilingDB: -1.0, .mix: 80, .outputDB: 0.5, .oversampling: 2, .gold: 40, .alchemy: 30, .boxTone: 1]),
        Preset(bank: "Drums", name: "Drum Bus Glue", values: [.driveDB: 4, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 45, .goldMode: 1, .unity: 1, .alchemy: 25, .boxTone: 2]),
        Preset(bank: "Drums", name: "Room Crush", values: [.driveDB: 12, .ceilingDB: -3.0, .mix: 50, .outputDB: 2.0, .clipMode: 0, .gold: 80, .goldMode: 1, .alchemy: 40, .boxTone: 2]),
        Preset(bank: "Drums", name: "Breakbeat Grit", values: [.driveDB: 9, .ceilingDB: -1.5, .mix: 85, .outputDB: 1.0, .clipMode: 0, .gold: 65, .goldMode: 1, .alchemy: 15, .boxTone: 2]),
        // 808 & Bass
        Preset(bank: "808 & Bass", name: "808 Round", values: [.driveDB: 5, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 30, .alchemy: 40]),
        Preset(bank: "808 & Bass", name: "808 Growl", values: [.driveDB: 10, .ceilingDB: -1.0, .outputDB: 0.5, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 70, .boxTone: 2]),
        Preset(bank: "808 & Bass", name: "808 Click Keeper", values: [.driveDB: 6, .ceilingDB: -0.5, .clipMode: 0, .oversampling: 2, .gold: 20, .unity: 1, .alchemy: 20]),
        Preset(bank: "808 & Bass", name: "Sub Control", values: [.driveDB: 3, .ceilingDB: -1.0, .outputDB: 1.0, .clipMode: 1, .oversampling: 2, .alchemy: 30]),
        Preset(bank: "808 & Bass", name: "Bass DI Warm", values: [.driveDB: 4, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 45, .goldMode: 1, .unity: 1, .alchemy: 45, .boxTone: 2]),
        Preset(bank: "808 & Bass", name: "Synth Bass Edge", values: [.driveDB: 7, .ceilingDB: -0.5, .oversampling: 2, .gold: 40, .alchemy: 55, .boxTone: 1]),
        Preset(bank: "808 & Bass", name: "Reese Saturate", values: [.driveDB: 9, .ceilingDB: -1.0, .mix: 80, .outputDB: 0.5, .oversampling: 2, .gold: 70, .goldMode: 1, .alchemy: 60, .boxTone: 2]),
        Preset(bank: "808 & Bass", name: "Bass Parallel Fat", values: [.driveDB: 11, .ceilingDB: -1.0, .mix: 50, .oversampling: 2, .gold: 75, .goldMode: 1, .alchemy: 50]),
        // Vocals
        Preset(bank: "Vocals", name: "Lead Vocal Peaks", values: [.driveDB: 2, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .unity: 1, .alchemy: 50]),
        Preset(bank: "Vocals", name: "Rap Vocal Forward", values: [.driveDB: 5, .ceilingDB: -1.0, .outputDB: 0.5, .oversampling: 2, .gold: 40, .unity: 1, .alchemy: 55, .boxTone: 1]),
        Preset(bank: "Vocals", name: "Vocal Air Smooth", values: [.driveDB: 3, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 20, .unity: 1, .alchemy: 75, .boxTone: 2]),
        Preset(bank: "Vocals", name: "Backing Vocal Glue", values: [.driveDB: 4, .ceilingDB: -1.5, .mix: 80, .outputDB: 1.0, .clipMode: 1, .oversampling: 2, .gold: 35, .goldMode: 1, .unity: 1, .alchemy: 45, .boxTone: 2]),
        Preset(bank: "Vocals", name: "Ad-lib Grit", values: [.driveDB: 9, .ceilingDB: -2.0, .mix: 70, .outputDB: 1.5, .clipMode: 0, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 30]),
        Preset(bank: "Vocals", name: "Vocal Bus Density", values: [.driveDB: 4, .ceilingDB: -0.5, .mix: 60, .oversampling: 2, .gold: 50, .goldMode: 1, .unity: 1, .alchemy: 40, .boxTone: 1]),
        Preset(bank: "Vocals", name: "Telephone Crunch", values: [.driveDB: 12, .ceilingDB: -4.0, .outputDB: 3.5, .clipMode: 0, .oversampling: 0, .gold: 80, .goldMode: 1, .boxTone: 2]),
        Preset(bank: "Vocals", name: "Soft Sibilance Tame", values: [.driveDB: 1, .ceilingDB: -1.5, .outputDB: 1.0, .clipMode: 1, .oversampling: 2, .unity: 1, .alchemy: 90, .boxTone: 2]),
        // Guitars
        Preset(bank: "Guitars", name: "Acoustic Strum Peaks", values: [.driveDB: 2, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 15, .unity: 1, .alchemy: 40, .boxTone: 1]),
        Preset(bank: "Guitars", name: "Electric Rhythm Push", values: [.driveDB: 6, .ceilingDB: -1.0, .outputDB: 0.5, .oversampling: 2, .gold: 50, .goldMode: 1, .alchemy: 35, .boxTone: 2]),
        Preset(bank: "Guitars", name: "Lead Guitar Sustain", values: [.driveDB: 8, .ceilingDB: -1.0, .mix: 85, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 45, .boxTone: 2]),
        Preset(bank: "Guitars", name: "Clean Guitar Sparkle", values: [.driveDB: 3, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 25, .unity: 1, .alchemy: 20, .boxTone: 1]),
        Preset(bank: "Guitars", name: "Fuzz Wall", values: [.driveDB: 12, .ceilingDB: -2.0, .outputDB: 1.5, .clipMode: 0, .gold: 90, .goldMode: 1, .alchemy: 50, .boxTone: 2]),
        // Keys & Synths
        Preset(bank: "Keys & Synths", name: "Piano Peak Catch", values: [.driveDB: 2, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 15, .unity: 1, .alchemy: 25, .boxTone: 1]),
        Preset(bank: "Keys & Synths", name: "Rhodes Warmth", values: [.driveDB: 4, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 50, .goldMode: 1, .unity: 1, .alchemy: 45, .boxTone: 2]),
        Preset(bank: "Keys & Synths", name: "Pad Density", values: [.driveDB: 3, .ceilingDB: -1.0, .mix: 70, .outputDB: 0.5, .oversampling: 2, .gold: 55, .goldMode: 1, .alchemy: 35, .boxTone: 1]),
        Preset(bank: "Keys & Synths", name: "Pluck Snap", values: [.driveDB: 6, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 0, .oversampling: 2, .gold: 30, .unity: 1, .alchemy: 30]),
        Preset(bank: "Keys & Synths", name: "Supersaw Tame", values: [.driveDB: 5, .ceilingDB: -1.0, .outputDB: 0.5, .oversampling: 2, .gold: 35, .alchemy: 70, .boxTone: 2]),
        Preset(bank: "Keys & Synths", name: "Organ Drive", values: [.driveDB: 8, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .gold: 70, .goldMode: 1, .alchemy: 40, .boxTone: 2]),
        // FX & Creative
        Preset(bank: "FX & Creative", name: "Lo-Fi Crush", values: [.driveDB: 12, .ceilingDB: -6.0, .outputDB: 5.0, .clipMode: 0, .oversampling: 0, .gold: 90, .goldMode: 1, .boxTone: 2]),
        Preset(bank: "FX & Creative", name: "Hear The Clip (Delta)", values: [.delta: 1, .driveDB: 6, .ceilingDB: -1.0, .clipMode: 0, .oversampling: 2]),
        Preset(bank: "FX & Creative", name: "Distant Radio", values: [.driveDB: 10, .ceilingDB: -8.0, .outputDB: 7.0, .clipMode: 0, .oversampling: 0, .gold: 70, .goldMode: 1, .alchemy: 80, .boxTone: 2]),
        Preset(bank: "FX & Creative", name: "Parallel Explode", values: [.driveDB: 12, .ceilingDB: -2.0, .mix: 30, .clipMode: 0, .gold: 100, .goldMode: 1, .alchemy: 20]),
        Preset(bank: "FX & Creative", name: "Tape Shoulder", values: [.driveDB: 6, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 80, .goldMode: 1, .unity: 1, .alchemy: 60, .boxTone: 2]),
        // Trap Pack
        Preset(bank: "Trap Pack", name: "Trap Master", values: [.inputDB: 3, .driveDB: 4, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 45, .boxTone: 1]),
        Preset(bank: "Trap Pack", name: "Trap 808 Slam", values: [.driveDB: 10, .ceilingDB: -0.5, .oversampling: 2, .gold: 55, .goldMode: 1, .alchemy: 70]),
        Preset(bank: "Trap Pack", name: "Trap Snare Crack", values: [.driveDB: 9, .ceilingDB: -1.5, .outputDB: 1.5, .clipMode: 0, .oversampling: 2, .gold: 35, .goldMode: 1, .unity: 1, .alchemy: 25]),
        Preset(bank: "Trap Pack", name: "Trap Hats Bright", values: [.driveDB: 4, .ceilingDB: -1.5, .outputDB: 1.0, .clipMode: 1, .oversampling: 2, .alchemy: 40, .boxTone: 1]),
        Preset(bank: "Trap Pack", name: "Trap Vocal Loud", values: [.driveDB: 6, .ceilingDB: -1.0, .outputDB: 0.5, .oversampling: 2, .gold: 50, .unity: 1, .alchemy: 55, .boxTone: 1]),
        Preset(bank: "Trap Pack", name: "Trap Drum Bus", values: [.driveDB: 8, .ceilingDB: -1.0, .mix: 80, .outputDB: 0.5, .clipMode: 0, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 30]),
        // Boom Bap Pack
        Preset(bank: "Boom Bap Pack", name: "Boom Bap Master", values: [.inputDB: 2, .driveDB: 3, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 55, .goldMode: 1, .alchemy: 55, .boxTone: 2]),
        Preset(bank: "Boom Bap Pack", name: "Dusty Drum Bus", values: [.driveDB: 9, .ceilingDB: -1.5, .mix: 85, .outputDB: 1.0, .clipMode: 0, .gold: 70, .goldMode: 1, .alchemy: 50, .boxTone: 2]),
        Preset(bank: "Boom Bap Pack", name: "Boom Bap Kick Knock", values: [.driveDB: 7, .ceilingDB: -1.0, .outputDB: 1.0, .clipMode: 0, .oversampling: 2, .gold: 40, .goldMode: 1, .unity: 1, .alchemy: 20, .boxTone: 2]),
        Preset(bank: "Boom Bap Pack", name: "SP Snare", values: [.driveDB: 10, .ceilingDB: -2.0, .outputDB: 1.5, .clipMode: 0, .oversampling: 0, .gold: 60, .goldMode: 1, .alchemy: 30, .boxTone: 2]),
        Preset(bank: "Boom Bap Pack", name: "Sample Chop Warmth", values: [.driveDB: 5, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 60, .goldMode: 1, .unity: 1, .alchemy: 60, .boxTone: 2]),
        // R&B / Neo Soul Pack
        Preset(bank: "R&B / Neo Soul Pack", name: "Silk Master", values: [.inputDB: 2, .driveDB: 2, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 40, .goldMode: 1, .alchemy: 50, .boxTone: 2]),
        Preset(bank: "R&B / Neo Soul Pack", name: "Neo Soul Drums", values: [.driveDB: 5, .ceilingDB: -1.0, .mix: 80, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 50, .goldMode: 1, .unity: 1, .alchemy: 45, .boxTone: 2]),
        Preset(bank: "R&B / Neo Soul Pack", name: "R&B Lead Vocal", values: [.driveDB: 3, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 25, .unity: 1, .alchemy: 65, .boxTone: 2]),
        Preset(bank: "R&B / Neo Soul Pack", name: "Warm Keys Bus", values: [.driveDB: 4, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 55, .goldMode: 1, .unity: 1, .alchemy: 50, .boxTone: 2]),
        Preset(bank: "R&B / Neo Soul Pack", name: "Round Bass", values: [.driveDB: 5, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 45, .goldMode: 1, .alchemy: 45, .boxTone: 2]),
        // Pop Pack
        Preset(bank: "Pop Pack", name: "Pop Master Bright", values: [.inputDB: 3, .driveDB: 3, .oversampling: 2, .gold: 45, .alchemy: 35, .boxTone: 1]),
        Preset(bank: "Pop Pack", name: "Pop Drum Bus", values: [.driveDB: 6, .ceilingDB: -0.5, .oversampling: 2, .gold: 50, .unity: 1, .alchemy: 30, .boxTone: 1]),
        Preset(bank: "Pop Pack", name: "Pop Vocal Up Front", values: [.driveDB: 4, .ceilingDB: -1.0, .outputDB: 0.5, .oversampling: 2, .gold: 35, .unity: 1, .alchemy: 55, .boxTone: 1]),
        Preset(bank: "Pop Pack", name: "Pop Synth Bus", values: [.driveDB: 4, .ceilingDB: -0.5, .oversampling: 2, .gold: 40, .alchemy: 45, .boxTone: 1]),
        Preset(bank: "Pop Pack", name: "Pop Kick Click", values: [.driveDB: 7, .ceilingDB: -1.0, .outputDB: 1.0, .clipMode: 0, .oversampling: 2, .gold: 25, .unity: 1, .alchemy: 15]),
        // EDM Pack
        Preset(bank: "EDM Pack", name: "Festival Master", values: [.inputDB: 4, .driveDB: 6, .oversampling: 2, .gold: 75, .goldMode: 1, .alchemy: 50, .boxTone: 1]),
        Preset(bank: "EDM Pack", name: "Big Room Kick", values: [.driveDB: 10, .ceilingDB: -0.5, .clipMode: 0, .oversampling: 2, .gold: 50, .goldMode: 1, .alchemy: 25]),
        Preset(bank: "EDM Pack", name: "Drop Bus Slam", values: [.driveDB: 9, .ceilingDB: -0.5, .mix: 90, .oversampling: 2, .gold: 70, .goldMode: 1, .alchemy: 45, .boxTone: 1]),
        Preset(bank: "EDM Pack", name: "Lead Synth Bite", values: [.driveDB: 6, .ceilingDB: -1.0, .outputDB: 0.5, .oversampling: 2, .gold: 45, .alchemy: 60, .boxTone: 1]),
        Preset(bank: "EDM Pack", name: "Riser Glue", values: [.driveDB: 5, .ceilingDB: -1.0, .mix: 70, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 50, .goldMode: 1, .alchemy: 50, .boxTone: 2]),
        // Rock Pack
        Preset(bank: "Rock Pack", name: "Rock Master", values: [.inputDB: 3, .driveDB: 4, .clipMode: 1, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 45, .boxTone: 2]),
        Preset(bank: "Rock Pack", name: "Rock Drum Bus Crush", values: [.driveDB: 9, .ceilingDB: -1.0, .mix: 70, .outputDB: 0.5, .clipMode: 0, .oversampling: 2, .gold: 70, .goldMode: 1, .alchemy: 35, .boxTone: 2]),
        Preset(bank: "Rock Pack", name: "Rock Snare Fat", values: [.driveDB: 7, .ceilingDB: -1.0, .outputDB: 1.0, .clipMode: 1, .oversampling: 2, .gold: 55, .goldMode: 1, .unity: 1, .alchemy: 30, .boxTone: 2]),
        Preset(bank: "Rock Pack", name: "Guitar Bus Wall", values: [.driveDB: 7, .ceilingDB: -1.0, .outputDB: 0.5, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 45, .boxTone: 2]),
        Preset(bank: "Rock Pack", name: "Rock Vocal Grit", values: [.driveDB: 6, .ceilingDB: -1.0, .mix: 85, .outputDB: 0.5, .oversampling: 2, .gold: 55, .goldMode: 1, .unity: 1, .alchemy: 50, .boxTone: 2]),
        // Lo-Fi Pack
        Preset(bank: "Lo-Fi Pack", name: "Lo-Fi Master", values: [.inputDB: 1, .driveDB: 4, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .gold: 70, .goldMode: 1, .alchemy: 75, .boxTone: 2]),
        Preset(bank: "Lo-Fi Pack", name: "Lo-Fi Drums Dusty", values: [.driveDB: 10, .ceilingDB: -3.0, .outputDB: 2.5, .clipMode: 0, .oversampling: 0, .gold: 75, .goldMode: 1, .alchemy: 60, .boxTone: 2]),
        Preset(bank: "Lo-Fi Pack", name: "Lo-Fi Keys Tape", values: [.driveDB: 5, .ceilingDB: -1.5, .outputDB: 1.0, .clipMode: 1, .gold: 70, .goldMode: 1, .unity: 1, .alchemy: 70, .boxTone: 2]),
        Preset(bank: "Lo-Fi Pack", name: "Lo-Fi Bass Soft", values: [.driveDB: 4, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 50, .goldMode: 1, .alchemy: 60, .boxTone: 2]),
        // Drill Pack
        Preset(bank: "Drill Pack", name: "Drill Master", values: [.inputDB: 3, .driveDB: 5, .oversampling: 2, .gold: 65, .goldMode: 1, .alchemy: 45, .boxTone: 1]),
        Preset(bank: "Drill Pack", name: "Drill 808 Slide", values: [.driveDB: 11, .ceilingDB: -0.5, .oversampling: 2, .gold: 60, .goldMode: 1, .alchemy: 75]),
        Preset(bank: "Drill Pack", name: "Drill Snare Snap", values: [.driveDB: 9, .ceilingDB: -1.5, .outputDB: 1.5, .clipMode: 0, .oversampling: 2, .gold: 40, .goldMode: 1, .unity: 1, .alchemy: 25]),
        Preset(bank: "Drill Pack", name: "Drill Vocal Aggro", values: [.driveDB: 8, .ceilingDB: -1.0, .outputDB: 0.5, .oversampling: 2, .gold: 55, .goldMode: 1, .unity: 1, .alchemy: 50, .boxTone: 1]),
        // Afrobeats Pack
        Preset(bank: "Afrobeats Pack", name: "Afro Master Warm", values: [.inputDB: 2, .driveDB: 3, .clipMode: 1, .oversampling: 2, .gold: 50, .goldMode: 1, .alchemy: 45, .boxTone: 2]),
        Preset(bank: "Afrobeats Pack", name: "Afro Perc Bus", values: [.driveDB: 5, .ceilingDB: -1.0, .mix: 85, .outputDB: 0.5, .oversampling: 2, .gold: 40, .unity: 1, .alchemy: 35, .boxTone: 1]),
        Preset(bank: "Afrobeats Pack", name: "Afro Log Drum", values: [.driveDB: 7, .ceilingDB: -0.5, .oversampling: 2, .gold: 45, .goldMode: 1, .alchemy: 50]),
        Preset(bank: "Afrobeats Pack", name: "Afro Vocal Smooth", values: [.driveDB: 3, .ceilingDB: -1.0, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 30, .unity: 1, .alchemy: 65, .boxTone: 2]),
        // Gospel Pack
        Preset(bank: "Gospel Pack", name: "Gospel Master", values: [.inputDB: 2, .driveDB: 3, .clipMode: 1, .oversampling: 2, .gold: 45, .goldMode: 1, .alchemy: 45, .boxTone: 2]),
        Preset(bank: "Gospel Pack", name: "Choir Bus Glue", values: [.driveDB: 4, .ceilingDB: -1.0, .mix: 80, .outputDB: 0.5, .clipMode: 1, .oversampling: 2, .gold: 45, .goldMode: 1, .unity: 1, .alchemy: 55, .boxTone: 2]),
        Preset(bank: "Gospel Pack", name: "Gospel Drums Live", values: [.driveDB: 6, .ceilingDB: -1.0, .mix: 80, .outputDB: 0.5, .oversampling: 2, .gold: 55, .goldMode: 1, .alchemy: 35, .boxTone: 2]),
        Preset(bank: "Gospel Pack", name: "Organ & Keys Bus", values: [.driveDB: 5, .ceilingDB: -0.5, .clipMode: 1, .oversampling: 2, .gold: 55, .goldMode: 1, .unity: 1, .alchemy: 50, .boxTone: 2])
    ]
}
