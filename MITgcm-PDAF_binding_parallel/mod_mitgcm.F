C     $Id$
C!BOP
C
C     !DESCRIPTION:
C     This module includes header files of MITgcm and
C     serves as the single place where MITgcm code is
C     directly include. This module is use-included in
C     mod_assimilation, which provides the shared variables
C     for the assimilation code.
C
C     In general only this file would need to be in 
C     fixed-form source code, while all other user code
C     could be in the more convenient free form. 
C
C     !REVISION HISTORY:
C     2025-06 - Lars Nerger - Initial code
C     Later revisions - see repository
C
C     !MODULE:
      MODULE mod_mitgcm

C     !USES:
      IMPLICIT NONE
      SAVE
C!EOP

C     *** Variables specific for MITgcm ***

#include "CPP_OPTIONS.h"
#include "SIZE.h"
#include "GRID.h"
#include "EEPARAMS.h"
#include "DYNVARS.h"

      END MODULE mod_mitgcm
