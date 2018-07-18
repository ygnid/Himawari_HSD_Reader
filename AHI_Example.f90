!******************************************************************************%
! *
! *    Copyright (C) 2016-2018 Simon Proud <simon.proud@physics.ox.ac.uk>
! *
! *    This source code is licensed under the GNU General Public License (GPL),
! *    Version 3.  See the file COPYING for more details.
! *
! ******************************************************************************/

! the output is saved to a netcdf file. The lines below can
! be used to read/save specific bands and ancillary data

! Command line arguments are:
! Input filename
! Output filename
! Channel numbers (each separate)
! For example:
!	./AHI HS_H08_20150711_0040_B01_FLDK_R10_S0310.DAT OUT.nc 1 2 3 8 14
!    Will load all segments for timeslot 0040 on 20150711
!    Will save to the 'OUT.nc' file in current directory
!    Will process data for channels 1, 2, 3, 8 and 14

program AHI_example_f90

	use himawari
	use himawari_utils
	use himawari_readwrite
	use omp_lib

	implicit none

	! Flag to do solar processing with Channels 1,2 and 3.
	! This uses the method described in DOI:10.1175/BAMS-D-15-00154.1
!	logical :: do_solar = .true.
	logical :: do_solar = .false.

	! Flag setting if we want to process at VIS or IR res
!	logical :: vis_res = .true.
	logical :: vis_res = .false.

	! Filename of the file to be read.
	character(HIMAWARI_CHARLEN)		::	filename
	! Name of NetCDF file to use for output
	character(HIMAWARI_CHARLEN)		::	outname
	character(HIMAWARI_CHARLEN)		::	outname2
	character(len=128)         		::	satposstr

	! Housekeeping vars
	integer retval, nchans, ncmd, ios, iostat, fpos, i
	CHARACTER(len=1024)				:: 	inarg

	! Data type that stores the AHI data and geolocs
	type(himawari_t_data)			::	ahi_data
	type(himawari_t_extent)       :: ahi_extent
	! Bands to read/write
	integer,dimension(:), allocatable	::	band_ids

	logical	:: verbose = .true.

	retval	=	0

	! Default values for fulldisk
	if (vis_res .eqv. .false.) then
		ahi_extent%x_min = 1
		ahi_extent%y_min = 1
		ahi_extent%x_max = HIMAWARI_IR_NLINES
		ahi_extent%y_max = HIMAWARI_IR_NCOLS
	else
		ahi_extent%x_min = 1
		ahi_extent%y_min = 1
		ahi_extent%x_max = HIMAWARI_VIS_NLINES
		ahi_extent%y_max = HIMAWARI_VIS_NCOLS
	endif

!	! Test vals
	ahi_extent%x_min = 1
	ahi_extent%x_max = 5500
	ahi_extent%y_min = 1
	ahi_extent%y_max = 5500

	ahi_extent%x_size = ahi_extent%x_max - ahi_extent%x_min + 1
	ahi_extent%y_size = ahi_extent%y_max - ahi_extent%y_min + 1

	! Loop over the command line arguments to extract files / chan numbers
	ncmd		=	1
	nchans	=	0
	do
		call get_command_argument(ncmd,inarg)
		if (len_trim(inarg).eq. 0) exit
		if (ncmd==1 .and. trim(inarg)=="h") then
			write(*,*)"Instructions:"
			stop
		endif
		if (ncmd==1) filename	=	trim(inarg)
		if (ncmd==2) outname	=	trim(inarg)
		if (ncmd.ge. 3) nchans	=	nchans + 1
		read( inarg, '(i10)',iostat=ios )retval
		if (ncmd.ge. 3 .and. ios .ne. 0) nchans	=	nchans -1
		ncmd	=	ncmd + 1
	enddo
	allocate(band_ids(nchans))
	band_ids(:)	=	him_sint_fill_value
	ncmd		=	1

	! Loop again to extract the actual channels from the argument
	! This is inefficient, but it works!
	do
		call get_command_argument(ncmd+2,inarg)
		if (len_trim(inarg).eq. 0) exit
		read( inarg, '(i10)',iostat=ios )retval
		if (ios .ne. 0) then
			write(*,*) "Incorrect channel specification:",trim(inarg)
			stop
		endif
		! Check that the user has not requested the same band twice
		if (any(band_ids .eq. retval)) then
			write(*,*)"Multiple definitions of the same band, you have:",band_ids(1:ncmd-1),"but also:",retval
			stop
		endif
		band_ids(ncmd)	=	retval

		if (ncmd .gt. nchans) exit
		ncmd	=	ncmd + 1
	enddo

	! If we're doing solar processing check that we have the 0.4,0.5, 0.6 and 0.8 bands.
	if (do_solar .eqv. .true.) then
		if (all(band_ids .ne. 1)) then
			write(*,*)"Cannot do solar processing, missing band 1. Quitting."
			stop
		endif
		if (all(band_ids .ne. 2)) then
			write(*,*)"Cannot do solar processing, missing band 2. Quitting."
			stop
		endif
		if (all(band_ids .ne. 3)) then
			write(*,*)"Cannot do solar processing, missing band 3. Quitting."
			stop
		endif
		if (all(band_ids .ne. 4)) then
			write(*,*)"Cannot do solar processing, missing band 4. Quitting."
			stop
		endif
	endif

	! Allocate space for all the output data
	retval	=	AHI_alloc_vals_data(ahi_data,ahi_extent,nchans,do_solar,verbose)
	if (retval .ne. HIMAWARI_SUCCESS) then
		write(*,*)"Error encountered in data allocation. Quitting."
		stop
	endif

	! Call the main reader function
	retval	=	AHI_Main_Read(filename,"/network/aopp/apres/users/proud/ORAC_Data/GEO_FILES/AHI_141E_ANGLES.nc",ahi_data,ahi_extent,nchans,band_ids,0,1,.true.,do_solar,vis_res,satposstr,verbose)
	if (retval .ne. HIMAWARI_SUCCESS) then
		write(*,*)"Error encountered in data reading. Quitting."
		stop
	endif

	if (do_solar .eqv. .true.) then
		retval	=	AHI_Create_TrueColour(ahi_data,ahi_extent,verbose)
		if (retval .ne. HIMAWARI_SUCCESS) then
			write(*,*)"Error encountered in creating true colour image. Quitting."
			stop
		endif
		retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,1),ahi_extent,outname,"Band_01",1,verbose)
		retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,2),ahi_extent,outname,"Band_02",0,verbose)
		retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,3),ahi_extent,outname,"Band_03",0,verbose)

		if (verbose) write(*,*)"Complete."
!		stop
	endif

	outname2	=	"/network/group/aopp/testvol2/eodg/TEST_ORIG.nc"

!	! Calls for saving the data. Uncomment as necessary.
!	! These are the bands.
!	! Note: Final var controls if a new file. Pass 1 only for first call to function, otherwise 0.
!	! Note 2: Final dimension of %indata is the channel.
!	!         They are sequential, not based on channel IDs!
	retval	=	AHI_SavetoNCDF((ahi_data%indata(:,:,1)),ahi_extent,outname2,"Band_01",1,verbose)
	retval	=	AHI_SavetoNCDF((ahi_data%indata(:,:,2)),ahi_extent,outname2,"Band_02",0,verbose)
	retval	=	AHI_SavetoNCDF((ahi_data%indata(:,:,3)),ahi_extent,outname2,"Band_03",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,4),ahi_extent,outname,"Band_09",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,5),ahi_extent,outname,"Band_05",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,6),ahi_extent,outname,"Band_06",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,7),ahi_extent,outname,"Band_07",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,8),ahi_extent,outname,"Band_08",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,9),ahi_extent,outname,"Band_09",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,10),ahi_extent,outname,"Band_10",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,11),ahi_extent,outname,"Band_11",0,verbose)
	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,4),ahi_extent,outname,"Band_12",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,13),ahi_extent,outname,"Band_13",0,verbose)
	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,5),ahi_extent,outname,"Band_14",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,15),ahi_extent,outname,"Band_15",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%indata(:,:,1),ahi_extent,outname,"Band_16",1,verbose)
!
!	! These are geolocation, uncomment to save
!	retval	=	AHI_SavetoNCDF(ahi_data%lon,ahi_extent,outname,"Lon",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%lat,ahi_extent,outname,"Lat",0,verbose)
!
!	! These are solar angles, uncomment to save
!	retval	=	AHI_SavetoNCDF(ahi_data%sza,ahi_extent,outname,"SZA",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%saa,ahi_extent,outname,"SAA",0,verbose)
!
!	! These are viewing angles, uncomment to save
!	retval	=	AHI_SavetoNCDF(ahi_data%vza,ahi_extent,outname,"VZA",0,verbose)
!	retval	=	AHI_SavetoNCDF(ahi_data%vaa,ahi_extent,outname,"VAA",0,verbose)
!
!	! Clear up all the variables
!	retval	=	AHI_free_vals_data(ahi_data,verbose)
!	deallocate(band_ids)

end program AHI_example_f90
