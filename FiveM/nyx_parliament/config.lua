Config = {}

-- Diagnostics & Debugging
Config.Debug = false

-- Democratic Thresholds & Quorum
Config.DefaultQuorum = 5                 -- Minimum validated voters for a certified result
Config.MajorityThresholdPercent = 50.0   -- Strict majority (>50%) required by Instant-Runoff Voting
Config.BillProposalDeposit = 5000.00     -- Collateral deposit required to propose a legislative bill
Config.CandidateCollateral = 2500.00     -- Collateral deposit required to register as candidate
Config.RequiredEndorsements = 3          -- Number of citizen endorsements needed to qualify
Config.OfficialTermDays = 30             -- Duration of elected office term in days
Config.RecallSignatureThreshold = 5      -- Minimum signatures needed to initiate a recall referendum
Config.MaxCandidatesPerSession = 10      -- Max candidate ceiling per election session

-- Elective Municipal Offices
Config.Offices = {
    ['mayor'] = {
        title = "City Mayor",
        department = "Executive",
        termDays = 30
    },
    ['chief_magistrate'] = {
        title = "Chief Magistrate",
        department = "Judiciary",
        termDays = 45
    },
    ['district_commissioner'] = {
        title = "District Commissioner",
        department = "Legislative",
        termDays = 30
    }
}

-- Session Lifecycle Checks
Config.SessionCheckInterval = 60         -- Evaluate expired voting sessions every 60 seconds

-- Physical Voting Booth Locations (City Hall, Sandy Court, Paleto Center)
Config.Booths = {
    {
        label = "City Hall Council Voting Booth",
        coords = vector3(-540.9, -199.3, 47.5)
    },
    {
        label = "Sandy Shores Regional Ballot Station",
        coords = vector3(1853.2, 3686.9, 34.3)
    },
    {
        label = "Paleto Bay Justice Center Ballot Station",
        coords = vector3(-448.2, 6012.3, 31.7)
    }
}

Config.BoothInteractDistance = 2.0

-- Authorized Sponsorship Roles
Config.SponsorRoles = {
    ['mayor'] = true,
    ['parliament'] = true,
    ['representative'] = true,
    ['admin'] = true
}
