C     !ROUTINE: init_pdaf - Interface routine to call initialization of PDAF
C
C     !INTERFACE:
      SUBROUTINE init_pdaf( nIter0, myTimeLoc, myIterLoc, myThidLoc )

C     !DESCRIPTION:
C     This routine collects the initialization of variables for PDAF.
C     In addition, the initialization routine PDAF_init is called
C     such that the internal initialization of PDAF is performed.
C     This variant is for the online mode of PDAF.
C
C     This routine is generic. However, it assumes a constant observation
C     error (rms_obs_etan). Further, with parallelization the local state
C     dimension dim_state_p is used.
C
C     !REVISION HISTORY:
C     2008-10 - Lars Nerger - Initial code
C     Later revisions - see svn log
C
C     !USES:
C     Interface definitions for PDAF
      USE pdaf,
     &     ONLY: PDAF_init, PDAF_init_forecast, PDAF_set_iparam
C     Parallelization variables for model
      USE mod_parallel_model,
     &     ONLY: mype_world, COMM_model, abort_parallel
C     Parallelization variables fro assimilation
      USE mod_parallel_pdaf, ONLY: n_modeltasks, task_id, COMM_filter,
     &     COMM_couple, filterpe
C     Variables for assimilation
      USE mod_assimilation,  ONLY: dim_state_p, dim_state, screen,
     &     filtertype, subtype, dim_ens, iter_null,
     &     nsteps_between_obs, type_forget, forget,
     &     locweight, cradius, sradius, type_trans, type_sqrt,
     &     myIter, myThid, MyTime, write_ens,
     &     n_fields, id, fields, observe_ens, type_obs_init,
     &     sNx, sNy, Nr, Nx, Ny
      USE obs_etan_pdafomi,
     &      ONLY: assim_etan, rms_obs_etan

      IMPLICIT NONE

C     !ARGUMENTS:
      INTEGER, INTENT(in) :: nIter0
      INTEGER, INTENT(in) :: myIterLoc
      INTEGER, INTENT(in) :: myThidLoc
      REAL(kind=8), INTENT(in) :: myTimeLoc

C     Local variables
      INTEGER :: i                       ! Counter
      INTEGER :: filter_param_i(2)       ! Integer parameter array for filter
      REAL(kind=8) :: filter_param_r(1)  ! Real parameter array for filter
      INTEGER :: status_pdaf             ! PDAF status flag

C     External subroutines
      EXTERNAL :: init_ens_pdaf    ! Ensemble initialization
      EXTERNAL :: next_observation_pdaf, ! Provide time step, model time,
                                   ! and dimension of next observation
     &     distribute_state_pdaf,  ! Distribute a state vector to model fields
     &     prepoststep_ens_pdaf    ! User supplied pre/poststep routine

C     Namelist for PDAF settings
      NAMELIST /pdaf_nml/ screen, filtertype, subtype,
     &     iter_null, nsteps_between_obs,
     &     type_forget, forget, type_trans, type_sqrt,
     &     locweight, cradius, sradius, write_ens,
     &     assim_etan, rms_obs_etan, observe_ens, type_obs_init


C     *** Store information from MITgcm to be used in call-back routines ***
      myIter = myIterLoc
      myThid = myThidLoc
      myTime = myTimeLoc


C     ***************************
C     ***   Initialize PDAF   ***
C     ***************************

      IF (mype_world == 0) THEN
         WRITE (*,'(/a,1x,a)') 'PDAFuser:',
     &        'INITIALIZE PDAF - ONLINE MODE'
      END IF

      ! Store initial iteration
      iter_null = myIter


C     *****************************
C     ***   Define state vector ***
C     *****************************

C     Define state dimension
      dim_state_p = sNx*sNy + 4*sNx*sNy*Nr  ! Process local dimension
      dim_state   = Nx*Ny + 4*Nx*Ny*Nr      ! Global dimension

C     Number of model fields in state vector
      n_fields = 5  ! Number of fields in state vector     

C     Specify field IDs in state vector ('id' allows to give the field a name)
      id%etan = 1
      id%theta= 2
      id%salt = 3
      id%uvel = 4
      id%vvel = 5

C     Define field dimensions
      allocate(fields(n_fields))

      fields(id%etan)%dim = Nx*Ny    ! EtaN
      fields(id%theta)%dim= Nx*Ny*Nr ! Theta
      fields(id%salt)%dim = Nx*Ny*Nr ! Salt
      fields(id%uvel)%dim = Nx*Ny*Nr ! uVel
      fields(id%vvel)%dim = Nx*Ny*Nr ! vVel

      fields(1)%off = 0
      DO i = 2, n_fields
         fields(i)%off = fields(i-1)%off + fields(i-1)%dim
      END DO


C     **********************************************************
C     ***   CONTROL OF PDAF - used in call to PDAF_init      ***
C     **********************************************************

C     For possible option values see mod_assimilation.F

C     *** IO options ***
      screen = 2    ! Write screen output (1) for output, (2) add timings

C     *** Filter specific variables
      filtertype = 7            ! Type of filter
      subtype = 0               ! subtype of filter:
      type_trans = 0            ! Type of ensemble transformation
      type_forget = 0           ! Type of forgetting factor in ETKF/LETKF/ESTKF/LESTKF
      forget  = 1.0             ! Forgetting factor
      type_sqrt = 0             ! Type of transform matrix square-root
                                !   (0) symmetric square root, (1) Cholesky decomposition


C     *********************************************************************
C     ***   Settings for analysis steps  - used in call-back routines   ***
C     *********************************************************************

C     Forecast length
      nsteps_between_obs = 10   ! Number of time steps between analysis/assimilation steps

C     Whether to write full ensemble files
      write_ens = .false.

C     Observation error standard deviation
      rms_obs_etan = 0.10       ! For sea surface height etan

C     Localization settings for LESTKF/LETKF
      locweight = 4             ! Type of localizating weighting
      cradius = 50000.0         ! Localization cut-off radius
      sradius = cradius         ! Support radius for 5th-order polynomial
                                ! or radius for 1/e for exponential weighting


C     ***********************************
C     *** Some optional functionality ***
C     ***********************************

C     *** Read namelist file for PDAF ***

      OPEN (500,file='pdaf.nml')
      READ (500,NML=pdaf_nml)
      CLOSE (500)

C     *** Parse command line options   ***
C     *** This is optional, but useful ***

      call init_pdaf_parse()


C     *** Initial Screen output ***
C     *** This is optional      ***

      IF (mype_world == 0) call init_pdaf_info()


C     *****************************************************
C     *** Call PDAF initialization routine on all PEs.  ***
C     ***                                               ***
C     *** For all filters, first the arrays of integer  ***
C     *** and real number parameters are initialized.   ***
C     *** Subsequently, PDAF_init is called.            ***
C     *****************************************************

      filter_param_i(1) = dim_state_p ! State dimension
      filter_param_i(2) = dim_ens     ! Size of ensemble
      filter_param_r(1) = forget      ! Forgetting factor

      CALL PDAF_init(filtertype, subtype, nIter0,
     &     filter_param_i, 2,
     &     filter_param_r, 1,
     &     COMM_model, COMM_filter, COMM_couple,
     &     task_id, n_modeltasks, filterpe, init_ens_pdaf,
     &     screen, status_pdaf)


C     ! *** Additional parameter specifications ***
C     ! *** -- These are all optional --        ***

C     Generic settings
      CALL PDAF_set_iparam(5, type_forget, status_pdaf)
      CALL PDAF_set_iparam(6, type_trans, status_pdaf)
      CALL PDAF_set_iparam(7, type_sqrt, status_pdaf)
      CALL PDAF_set_iparam(8, observe_ens, status_pdaf)
      CALL PDAF_set_iparam(9, type_obs_init, status_pdaf)

C     *** Check whether initialization of PDAF was successful ***
      IF (status_pdaf /= 0) THEN
         WRITE (*,'(/1x,a6,i3,a43,i4,a1/)')
     &        'ERROR ', status_pdaf,
     &        ' in initialization of PDAF ',
     &        '- stopping           ! (PE ', mype_world,')'
         CALL abort_parallel()
      END IF


C     **********************************
C     *** Prepare ensemble forecasts ***
C     **********************************

      CALL PDAF_init_forecast(next_observation_pdaf,
     &     distribute_state_pdaf, prepoststep_ens_pdaf, status_pdaf)

      END
