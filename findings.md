# Findings: Anatomical Trauma & Organ-Specific Medical Injury Engine (`nyx_services`)

## Context & Architecture
1. **Anatomical Limb Mapping & Hit Detection**:
   - FiveM bone indices map deterministically to 6 core anatomical zones:
     - `head`: Bones 31086 (SKEL_Head), 39317 (SKEL_Neck_1)
     - `torso`: Bones 24818 (SKEL_Spine3), 24817 (SKEL_Spine2), 24816 (SKEL_Spine1), 11816 (SKEL_Pelvis)
     - `left_arm`: Bones 18905 (SKEL_L_Hand), 22711 (SKEL_L_Forearm), 45509 (SKEL_L_UpperArm), 64729 (SKEL_L_Clavicle)
     - `right_arm`: Bones 57005 (SKEL_R_Hand), 2992 (SKEL_R_Forearm), 40269 (SKEL_R_UpperArm), 10706 (SKEL_R_Clavicle)
     - `left_leg`: Bones 63931 (SKEL_L_Calf), 58271 (SKEL_L_Thigh), 14201 (SKEL_L_Foot)
     - `right_leg`: Bones 36864 (SKEL_R_Calf), 51826 (SKEL_R_Thigh), 52335 (SKEL_R_Foot)
   - Damage classification:
     - Ballistic trauma from bullet weapons.
     - Lacerations from melee/bladed weapons or vehicle collisions.
     - Fractures from high fall damage, vehicle crashes, or heavy blunt force.
     - Arterial bleeding occurring on high-severity penetrating or ballistic injuries.

2. **Physiological Hemodynamics & Shock Model**:
   - Baseline adult blood volume: 5000 mL.
   - Bleed rates in mL/s:
     - Minor laceration: 1.5 mL/s
     - Severe laceration / ballistic: 6.0 mL/s
     - Arterial hemorrhage: 25.0 mL/s
   - Shock Classification:
     - Class I (Normal / Mild): $\ge 4250$ mL ($>85\%$). Full cognitive and physical functioning.
     - Class II (Moderate Shock): $3500 - 4249$ mL ($70\% - 85\%$). Visual blurring, mild dizziness.
     - Class III (Severe Shock): $3000 - 3499$ mL ($60\% - 70\%$). Vision tunneling, disorientation, stumbling.
     - Class IV (Critical / Lethal Shock): $< 3000$ mL ($<60\%$). Hypovolemic coma, syncope / ragdoll blackout.

3. **Field Stabilization & Medical Consumables**:
   - Physical medical consumables required from player inventory:
     - `bandage_sterile` / `med_bandage`: Clears minor/severe lacerations, halves bleed rate, heals 25 HP.
     - `first_aid_pack` / `med_firstaid`: Stabilizes compound fractures and ballistic trauma, reduces bleeding by 80%, heals 60 HP.
     - `tourniquet`: Occludes blood flow to limbs (`left_arm`, `right_arm`, `left_leg`, `right_leg`), completely halting arterial hemorrhaging on that extremity. Cannot be applied to `head` or `torso`.
     - `splint`: Stabilizes skeletal fractures on arm/leg limbs, eliminating limp and aim sway debuffs.
     - `morphine_ampoule`: Reduces acute pain level to 0, providing temporary analgesia.

4. **Database Schema (Migration 041)**:
   - `nyx_medical_trauma`: Persistent player trauma state table.
   - `nyx_medical_treatments_log`: Immutable field medical treatment log for auditing and EMS records.
   - Registered in Step 41 of `index.json`.
