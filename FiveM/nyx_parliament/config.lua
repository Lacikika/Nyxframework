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
Config.RecallImmunityDays = 7            -- Days of recall immunity after surviving a referendum
Config.CollateralRefundThresholdPct = 10.0 -- Minimum vote share percentage for collateral refund
Config.NominationWindowHours = 48        -- Hours allowed for candidate nomination and signature gathering
Config.VotingWindowHours = 72            -- Hours allowed for active voting
Config.MaxCandidatesPerSession = 10      -- Max candidate ceiling per election session
Config.EnforceBoothProximity = false     -- When true, requires physical presence at a booth to cast ballot

-- Elective Municipal Offices
Config.Offices = {
    ['mayor'] = {
        title = "City Mayor",
        department = "Executive",
        termDays = 30,
        maxConsecutiveTerms = 2
    },
    ['chief_magistrate'] = {
        title = "Chief Magistrate",
        department = "Judiciary",
        termDays = 45,
        maxConsecutiveTerms = 2
    },
    ['district_commissioner'] = {
        title = "District Commissioner",
        department = "Legislative",
        termDays = 30,
        maxConsecutiveTerms = 3
    }
}

-- Session Lifecycle Checks
Config.SessionCheckInterval = 60         -- Evaluate expired voting sessions and terms every 60 seconds

-- Physical Voting Booth Locations (City Hall, Sandy Court, Paleto Center)
Config.Booths = {
    {
        id = "booth:city_hall",
        label = "City Hall Council Voting Booth",
        zone = "Downtown Los Santos",
        coords = vector3(-540.9, -199.3, 47.5)
    },
    {
        id = "booth:sandy_shores",
        label = "Sandy Shores Regional Ballot Station",
        zone = "Sandy Shores",
        coords = vector3(1853.2, 3686.9, 34.3)
    },
    {
        id = "booth:paleto_bay",
        label = "Paleto Bay Justice Center Ballot Station",
        zone = "Paleto Bay",
        coords = vector3(-448.2, 6012.3, 31.7)
    }
}

Config.BoothInteractDistance = 2.5

-- Authorized Sponsorship Roles
Config.SponsorRoles = {
    ['mayor'] = true,
    ['parliament'] = true,
    ['representative'] = true,
    ['admin'] = true
}
