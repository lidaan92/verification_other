#include "PACKAGES_CONFIG.h"
#include "CPP_OPTIONS.h"
#ifdef ALLOW_SHELFICE
# include "SHELFICE_OPTIONS.h"
#endif /* ALLOW_SHELFICE */

CBOP
C     !ROUTINE: INI_MASKS_ETC
C     !INTERFACE:
      SUBROUTINE INI_MASKS_ETC( myThid )
C     !DESCRIPTION: \bv
C     *==========================================================*
C     | SUBROUTINE INI_MASKS_ETC
C     | o Initialise masks and topography factors
C     *==========================================================*
C     | These arrays are used throughout the code and describe
C     | the topography of the domain through masks (0s and 1s)
C     | and fractional height factors (0<hFac<1). The latter
C     | distinguish between the lopped-cell and full-step
C     | topographic representations.
C     *==========================================================*
C     \ev

C     !USES:
      IMPLICIT NONE
C     === Global variables ===
#include "SIZE.h"
#include "EEPARAMS.h"
#include "PARAMS.h"
#include "GRID.h"
#ifdef NONLIN_FRSURF
# include "SURFACE.h"
#endif /* NONLIN_FRSURF */

C     !INPUT/OUTPUT PARAMETERS:
C     == Routine arguments ==
C     myThid  ::  Number of this instance of INI_MASKS_ETC
      INTEGER myThid

C     !LOCAL VARIABLES:
C     == Local variables ==
C     bi,bj   :: tile indices
C     i,j,k   :: Loop counters
C     tmpFld  :: Temporary array used to compute & write Total Depth
      _RS tmpFld(1-OLx:sNx+OLx,1-OLy:sNy+OLy,nSx,nSy)
      INTEGER bi, bj
      INTEGER i, j, k
      _RL hFacCtmp
      _RL hFacMnSz
CEOP

C---+----1----+----2----+----3----+----4----+----5----+----6----+----7-|--+----|

#ifdef ALLOW_SHELFICE
      IF ( useShelfIce ) THEN
C--   Modify  ocean upper boundary position according to ice-shelf topography
       CALL SHELFICE_INIT_DEPTHS(
     U               R_low, Ro_surf,
     I               myThid )
      ENDIF
#endif /* ALLOW_SHELFICE */

      IF ( selectSigmaCoord.EQ.0 ) THEN
C---  r-coordinate with partial-cell or full cell mask

C--   Calculate lopping factor hFacC : over-estimate the part inside of the domain
C     taking into account the lower_R Boundary (Bathymetrie / Top of Atmos)
      DO bj=myByLo(myThid), myByHi(myThid)
       DO bi=myBxLo(myThid), myBxHi(myThid)
        DO k=1, Nr
         hFacMnSz = MAX( hFacMin, MIN(hFacMinDr*recip_drF(k),oneRL) )
         DO j=1-OLy,sNy+OLy
          DO i=1-OLx,sNx+OLx
C      o Non-dimensional distance between grid bound. and domain lower_R bound.
           hFacCtmp = (rF(k)-R_low(i,j,bi,bj))*recip_drF(k)
C      o Select between, closed, open or partial (0,1,0-1)
           hFacCtmp = MIN( MAX( hFacCtmp, zeroRL ) , oneRL )
C      o Impose minimum fraction and/or size (dimensional)
           IF ( hFacCtmp.LT.hFacMnSz ) THEN
            IF ( hFacCtmp.LT.hFacMnSz*0.5 ) THEN
             hFacC(i,j,k,bi,bj) = 0.
            ELSE
             hFacC(i,j,k,bi,bj) = hFacMnSz
            ENDIF
           ELSE
             hFacC(i,j,k,bi,bj) = hFacCtmp
           ENDIF
          ENDDO
         ENDDO
        ENDDO

C-    Re-calculate lower-R Boundary position, taking into account hFacC
        DO j=1-OLy,sNy+OLy
         DO i=1-OLx,sNx+OLx
          R_low(i,j,bi,bj) = rF(1)
         ENDDO
        ENDDO
        DO k=Nr,1,-1
         DO j=1-OLy,sNy+OLy
          DO i=1-OLx,sNx+OLx
           R_low(i,j,bi,bj) = R_low(i,j,bi,bj)
     &                      - drF(k)*hFacC(i,j,k,bi,bj)
          ENDDO
         ENDDO
        ENDDO
C-    end bi,bj loops.
       ENDDO
      ENDDO

C--   Calculate lopping factor hFacC : Remove part outside of the domain
C     taking into account the Reference (=at rest) Surface Position Ro_surf
      DO bj=myByLo(myThid), myByHi(myThid)
       DO bi=myBxLo(myThid), myBxHi(myThid)
        DO k=1, Nr
         hFacMnSz = MAX( hFacMin, MIN(hFacMinDr*recip_drF(k),oneRL) )
         DO j=1-OLy,sNy+OLy
          DO i=1-OLx,sNx+OLx
C      o Non-dimensional distance between grid boundary and model surface
           hFacCtmp = (rF(k)-Ro_surf(i,j,bi,bj))*recip_drF(k)
C      o Reduce the previous fraction : substract the outside part.
           hFacCtmp = hFacC(i,j,k,bi,bj) - MAX( hFacCtmp, zeroRL )
C      o set to zero if empty Column :
           hFacCtmp = MAX( hFacCtmp, zeroRL )
C      o Impose minimum fraction and/or size (dimensional)
           IF ( hFacCtmp.LT.hFacMnSz ) THEN
            IF ( hFacCtmp.LT.hFacMnSz*0.5 ) THEN
             hFacC(i,j,k,bi,bj) = 0.
            ELSE
             hFacC(i,j,k,bi,bj) = hFacMnSz
            ENDIF
           ELSE
             hFacC(i,j,k,bi,bj) = hFacCtmp
           ENDIF
          ENDDO
         ENDDO
        ENDDO
       ENDDO
      ENDDO

c#ifdef ALLOW_SHELFICE
c     IF ( useShelfIce ) THEN
C--   Modify lopping factor hFacC : Remove part outside of the domain
C     taking into account the Reference (=at rest) Surface Position Ro_shelfIce
c      CALL SHELFICE_UPDATE_MASKS(
c    I     rF, recip_drF,
c    U     hFacC,
c    I     myThid )
c     ENDIF
c#endif /* ALLOW_SHELFICE */

C-    Re-calculate Reference surface position, taking into account hFacC
C     initialize Total column fluid thickness and surface k index
C       Note: if no fluid (continent) ==> kSurf = Nr+1
      DO bj=myByLo(myThid), myByHi(myThid)
       DO bi=myBxLo(myThid), myBxHi(myThid)
        DO j=1-OLy,sNy+OLy
         DO i=1-OLx,sNx+OLx
          tmpFld(i,j,bi,bj) = 0.
          kSurfC(i,j,bi,bj) = Nr+1
          Ro_surf(i,j,bi,bj) = R_low(i,j,bi,bj)
          DO k=Nr,1,-1
           Ro_surf(i,j,bi,bj) = Ro_surf(i,j,bi,bj)
     &                        + drF(k)*hFacC(i,j,k,bi,bj)
           IF ( hFacC(i,j,k,bi,bj).NE.zeroRS ) THEN
            kSurfC(i,j,bi,bj) = k
            tmpFld(i,j,bi,bj) = tmpFld(i,j,bi,bj) + 1.
           ENDIF
          ENDDO
          kLowC(i,j,bi,bj) = 0
          DO k= 1, Nr
           IF ( hFacC(i,j,k,bi,bj).NE.zeroRS ) THEN
              kLowC(i,j,bi,bj) = k
           ENDIF
          ENDDO
          maskInC(i,j,bi,bj) = 0.
          IF ( kSurfC(i,j,bi,bj).LE.Nr ) maskInC(i,j,bi,bj) = 1.
         ENDDO
        ENDDO
C-    end bi,bj loops.
       ENDDO
      ENDDO

#ifdef ALLOW_SHELFICE
#ifdef ALLOW_SHELFICE_REMESHING
      IF ( useShelfIce ) THEN
C--   Modify lopping factor hFacC : Remove part outside of the domain
C     taking into account the Reference (=at rest) Surface Position Ro_shelfIce
       CALL SHELFICE_DIG_SHELF( myThid )
      ENDIF
#endif
#endif /* ALLOW_SHELFICE */

      IF ( plotLevel.GE.debLevB ) THEN
c       CALL PLOT_FIELD_XYRS( tmpFld,
c    &           'Model Depths K Index' , -1, myThid )
        CALL PLOT_FIELD_XYRS(R_low,
     &           'Model R_low (ini_masks_etc)', -1, myThid )
        CALL PLOT_FIELD_XYRS(Ro_surf,
     &           'Model Ro_surf (ini_masks_etc)', -1, myThid )
      ENDIF

C--   Calculate quantities derived from XY depth map
      DO bj = myByLo(myThid), myByHi(myThid)
       DO bi = myBxLo(myThid), myBxHi(myThid)
        DO j=1-OLy,sNy+OLy
         DO i=1-OLx,sNx+OLx
C         Total fluid column thickness (r_unit) :
          tmpFld(i,j,bi,bj) = Ro_surf(i,j,bi,bj) - R_low(i,j,bi,bj)
C         Inverse of fluid column thickness (1/r_unit)
          IF ( tmpFld(i,j,bi,bj) .LE. zeroRS ) THEN
           recip_Rcol(i,j,bi,bj) = 0.
          ELSE
           recip_Rcol(i,j,bi,bj) = 1. _d 0 / tmpFld(i,j,bi,bj)
          ENDIF
         ENDDO
        ENDDO
       ENDDO
      ENDDO

      DO bj=myByLo(myThid), myByHi(myThid)
       DO bi=myBxLo(myThid), myBxHi(myThid)

C--   rLow & reference rSurf at Western & Southern edges (U and V points)
        i = 1-OLx
        DO j=1-OLy,sNy+OLy
           rLowW (i,j,bi,bj) = rF(1)
           rSurfW(i,j,bi,bj) = rF(1)
        ENDDO
        j = 1-OLy
        DO i=1-OLx,sNx+OLx
           rLowS (i,j,bi,bj) = rF(1)
           rSurfS(i,j,bi,bj) = rF(1)
        ENDDO
        DO j=1-OLy,sNy+OLy
         DO i=2-OLx,sNx+OLx
           rLowW(i,j,bi,bj)  =
     &           MAX(   R_low(i-1,j,bi,bj),   R_low(i,j,bi,bj) )
           rSurfW(i,j,bi,bj) =
     &           MIN( Ro_surf(i-1,j,bi,bj), Ro_surf(i,j,bi,bj) )
           rSurfW(i,j,bi,bj) =
     &           MAX( rSurfW(i,j,bi,bj), rLowW(i,j,bi,bj) )
         ENDDO
        ENDDO
        DO j=2-OLy,sNy+OLy
         DO i=1-OLx,sNx+OLx
           rLowS(i,j,bi,bj)  =
     &           MAX(   R_low(i,j-1,bi,bj),   R_low(i,j,bi,bj) )
           rSurfS(i,j,bi,bj) =
     &           MIN( Ro_surf(i,j-1,bi,bj), Ro_surf(i,j,bi,bj) )
           rSurfS(i,j,bi,bj) =
     &           MAX( rSurfS(i,j,bi,bj), rLowS(i,j,bi,bj) )
         ENDDO
        ENDDO

C--   hFacW and hFacS (at U and V points)
        DO k=1, Nr
         DO j=1-OLy,sNy+OLy
          hFacW(1-OLx,j,k,bi,bj) = 0.
          DO i=2-OLx,sNx+OLx
           hFacW(i,j,k,bi,bj) =
     &       MIN( hFacC(i,j,k,bi,bj), hFacC(i-1,j,k,bi,bj) )
          ENDDO
         ENDDO
         DO i=1-OLx,sNx+OLx
           hFacS(i,1-OLy,k,bi,bj) = 0.
         ENDDO
         DO j=2-OLy,sNy+OLy
          DO i=1-OLx,sNx+OLx
           hFacS(i,j,k,bi,bj) =
     &       MIN( hFacC(i,j,k,bi,bj), hFacC(i,j-1,k,bi,bj) )
          ENDDO
         ENDDO
        ENDDO

        IF ( useShelfIce ) THEN
C     Adjust reference rSurf at U and V points in order to get consistent
C     column thickness from Sum_k(hFac*drF) and rSurf-rLow
          DO j=1-OLy,sNy+OLy
           DO i=1-OLx,sNx+OLx
             rSurfW(i,j,bi,bj) = rLowW(i,j,bi,bj)
             rSurfS(i,j,bi,bj) = rLowS(i,j,bi,bj)
           ENDDO
          ENDDO
          DO k=1,Nr
           DO j=1-OLy,sNy+OLy
            DO i=1-OLx,sNx+OLx
             rSurfW(i,j,bi,bj) = rSurfW(i,j,bi,bj)
     &                         + hFacW(i,j,k,bi,bj)*drF(k)
             rSurfS(i,j,bi,bj) = rSurfS(i,j,bi,bj)
     &                         + hFacS(i,j,k,bi,bj)*drF(k)
            ENDDO
           ENDDO
          ENDDO
        ENDIF

C-    end bi,bj loops.
       ENDDO
      ENDDO
      CALL EXCH_UV_XYZ_RS( hFacW,  hFacS, .FALSE., myThid )
      CALL EXCH_UV_XY_RS( rSurfW, rSurfS, .FALSE., myThid )
      CALL EXCH_UV_XY_RS(  rLowW,  rLowS, .FALSE., myThid )

C--   Addtional closing of Western and Southern grid-cell edges: for example,
C     a) might add some "thin walls" in specific location
C--   b) close non-periodic N & S boundaries of lat-lon grid at the N/S poles.
      CALL ADD_WALLS2MASKS( myThid )

C--   Calculate surface k index for interface W & S (U & V points)
      DO bj=myByLo(myThid), myByHi(myThid)
       DO bi=myBxLo(myThid), myBxHi(myThid)
        DO j=1-OLy,sNy+OLy
         DO i=1-OLx,sNx+OLx
          kSurfW(i,j,bi,bj) = Nr+1
          kSurfS(i,j,bi,bj) = Nr+1
          DO k=Nr,1,-1
           IF (hFacW(i,j,k,bi,bj).NE.zeroRS) kSurfW(i,j,bi,bj) = k
           IF (hFacS(i,j,k,bi,bj).NE.zeroRS) kSurfS(i,j,bi,bj) = k
          ENDDO
          maskInW(i,j,bi,bj)= 0.
          IF ( kSurfW(i,j,bi,bj).LE.Nr ) maskInW(i,j,bi,bj)= 1.
          maskInS(i,j,bi,bj)= 0.
          IF ( kSurfS(i,j,bi,bj).LE.Nr ) maskInS(i,j,bi,bj)= 1.
         ENDDO
        ENDDO
       ENDDO
      ENDDO

      ELSE
#ifndef DISABLE_SIGMA_CODE
C---  Sigma and Hybrid-Sigma set-up:
        CALL INI_SIGMA_HFAC( myThid )
#endif /* DISABLE_SIGMA_CODE */
      ENDIF

C---+----1----+----2----+----3----+----4----+----5----+----6----+----7-|--+----|

C--   Write to disk: Total Column Thickness & hFac(C,W,S):
C     This I/O is now done in write_grid.F
c     CALL WRITE_FLD_XY_RS( 'Depth',' ',tmpFld,0,myThid)
c     CALL WRITE_FLD_XYZ_RS( 'hFacC',' ',hFacC,0,myThid)
c     CALL WRITE_FLD_XYZ_RS( 'hFacW',' ',hFacW,0,myThid)
c     CALL WRITE_FLD_XYZ_RS( 'hFacS',' ',hFacS,0,myThid)

      IF ( plotLevel.GE.debLevB ) THEN
        CALL PLOT_FIELD_XYZRS( hFacC, 'hFacC' , Nr, 0, myThid )
        CALL PLOT_FIELD_XYZRS( hFacW, 'hFacW' , Nr, 0, myThid )
        CALL PLOT_FIELD_XYZRS( hFacS, 'hFacS' , Nr, 0, myThid )
      ENDIF

C--   Masks and reciprocals of hFac[CWS]
      DO bj = myByLo(myThid), myByHi(myThid)
       DO bi = myBxLo(myThid), myBxHi(myThid)
        DO k=1,Nr
         DO j=1-OLy,sNy+OLy
          DO i=1-OLx,sNx+OLx
           IF ( hFacC(i,j,k,bi,bj).NE.zeroRS ) THEN
            recip_hFacC(i,j,k,bi,bj) = 1. _d 0 / hFacC(i,j,k,bi,bj)
            maskC(i,j,k,bi,bj) = 1.
           ELSE
            recip_hFacC(i,j,k,bi,bj) = 0.
            maskC(i,j,k,bi,bj) = 0.
           ENDIF
           IF ( hFacW(i,j,k,bi,bj).NE.zeroRS ) THEN
            recip_hFacW(i,j,k,bi,bj) = 1. _d 0 / hFacW(i,j,k,bi,bj)
            maskW(i,j,k,bi,bj) = 1.
           ELSE
            recip_hFacW(i,j,k,bi,bj) = 0.
            maskW(i,j,k,bi,bj) = 0.
           ENDIF
           IF ( hFacS(i,j,k,bi,bj).NE.zeroRS ) THEN
            recip_hFacS(i,j,k,bi,bj) = 1. _d 0 / hFacS(i,j,k,bi,bj)
            maskS(i,j,k,bi,bj) = 1.
           ELSE
            recip_hFacS(i,j,k,bi,bj) = 0.
            maskS(i,j,k,bi,bj) = 0.
           ENDIF
          ENDDO
         ENDDO
        ENDDO
#ifdef NONLIN_FRSURF
C--   Save initial geometrical hFac factor into h0Fac (fixed in time):
C     Note: In case 1 pkg modifies hFac (from packages_init_fixed, called
C     later in sequence of calls) this pkg would need also to update h0Fac.
        DO k=1,Nr
         DO j=1-OLy,sNy+OLy
          DO i=1-OLx,sNx+OLx
           h0FacC(i,j,k,bi,bj) = _hFacC(i,j,k,bi,bj)
           h0FacW(i,j,k,bi,bj) = _hFacW(i,j,k,bi,bj)
           h0FacS(i,j,k,bi,bj) = _hFacS(i,j,k,bi,bj)
          ENDDO
         ENDDO
        ENDDO
#endif /* NONLIN_FRSURF */
C-    end bi,bj loops.
       ENDDO
      ENDDO

c #ifdef ALLOW_NONHYDROSTATIC
C--   Calculate "recip_hFacU" = reciprocal hfac distance/volume for W cells
C NOTE:  not used ; computed locally in CALC_GW
c #endif

      RETURN
      END
