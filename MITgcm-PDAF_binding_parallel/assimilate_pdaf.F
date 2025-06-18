C     !ROUTINE: assimilate_pdaf - Routine to control perform analysis step
C
C     !DESCRIPTION:
C     This routine is called during the model integrations at each time
C     step. It check whether the forecast phase is completed. If so,
C     PDAF_put_state_X is called to perform the analysis step.
C
C     !REVISION HISTORY:
C     2013-08 - Lars Nerger - Initial code for NEMO
C     Later revisions - see svn log
C
C     !INTERFACE:
      SUBROUTINE assimilate_pdaf(myTimeLoc, myIterLoc, myThidLoc)
C     !USES:
      USE pdaf,
     & ONLY:  PDAF3_assimilate,
     &        PDAF3_assimilate_lenkf,
     &        PDAF_get_localfilter
      USE mod_parallel_model, ONLY: mype_world, abort_parallel
      USE mod_assimilation, ONLY: filtertype, myIter, myThid, myTime

      IMPLICIT NONE

C     !ARGUMENTS:
      INTEGER, INTENT(in) :: myIterLoc
      INTEGER, INTENT(in) :: myThidLoc
      REAL(kind=8), INTENT(in)    :: myTimeLoc

C     !CALLING SEQUENCE:
C     Called by: step
C     Calls: PDAF_assimilate_X

C     Local variables
      INTEGER status_pdaf    ! PDAF status flag
      INTEGER localfilter    ! Flag whether the chosen filter is localized

C     External subroutines
C     Interface between model and PDAF, and prepoststep
      EXTERNAL :: collect_state_pdaf,   ! Collect a state vector from model fields
     &     distribute_state_pdaf,       ! Distribute a state vector to model fields
     &     next_observation_pdaf,       ! Provide time step of next observation
     &     prepoststep_ens_pdaf         ! User supplied pre/poststep routine
C     Localization of state vector
      EXTERNAL :: init_n_domains_pdaf,  ! Provide number of local analysis domains
     &     init_dim_l_pdaf              ! Initialize state dimension for local ana. domain
C     Interface to PDAF-OMI for local and global filters
      EXTERNAL :: init_dim_obs_pdafomi, ! Get dimension of full obs. vector for PE-local domain
     &     obs_op_pdafomi,              ! Obs. operator for full obs. vector for PE-local domain
     &     init_dim_obs_l_pdafomi,      ! Get dimension of obs. vector for local analysis domain
     &     localize_covar_pdafomi       ! Apply localization to covariance matrix in LEnKF
C     Subroutine used for generating observations
      EXTERNAL :: get_obs_f_pdaf        ! Get vector of synthetic observations from PDAF


C     *********************************
C     *** Call assimilation routine ***
C     *********************************

      myIter = myIterLoc
      myThid = myThidLoc
      myTime = myTimeLoc


      IF (filtertype/=8) THEN
         CALL PDAF3_assimilate(collect_state_pdaf,
     &        distribute_state_pdaf, init_dim_obs_pdafomi,
     &        obs_op_pdafomi, init_n_domains_pdaf, 
     &        init_dim_l_pdaf, init_dim_obs_l_pdafomi, 
     &        prepoststep_ens_pdaf, next_observation_pdaf, status_pdaf)

      ELSE
C        LEnKF
         CALL PDAF3_assimilate_lenkf(collect_state_pdaf,
     &        distribute_state_pdaf, init_dim_obs_pdafomi,
     &        obs_op_pdafomi, localize_covar_pdafomi, 
     &        prepoststep_ens_pdaf, next_observation_pdaf,
     &        status_pdaf)
      END IF


C     Check for errors during execution of PDAF
      IF (status_pdaf /= 0) THEN
         WRITE (*,'(/1x,a6,i3,a43,i4,a1/)')
     &        'ERROR ', status_pdaf,
     &        ' in PDAF3_assimilate - stopping! (PE ', mype_world,')'
         CALL  abort_parallel()
      END IF

      END
