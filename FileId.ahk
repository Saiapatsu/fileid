; Get 64-bit NTFS file index (or whatever it's supposed to be called) in two halves.
; Optionally specify a VarRef to get the file handle. You are responsible for closing it.
; DllCall("CloseHandle", "Ptr", handle) || MsgBox("CloseHandle 1 failed " A_LastError)
; Returns nonzero on success or 0 on failure.
FilePathToIndex(path, &high, &low, outhandle := 0)
{
	static info := Buffer(52)
	
	handle := DllCall("CreateFile"
		, "Str" , path
		, "UInt", 0 ; dwDesiredAccess: neither read nor write
		, "UInt", 7 ; dwShareMode: all of them???
		, "Ptr" , 0 ; lpSecurityAttributes: NULL
		, "UInt", 3 ; dwCreationDisposition: OPEN_EXISTING
		, "UInt", 0 ; dwFlagsAndAttributes: ???
		, "Ptr" , 0) ; hTemplateFile: NULL
	
	if handle == -1
		return 0
	
	; https://learn.microsoft.com/en-us/windows/win32/api/fileapi/ns-fileapi-by_handle_file_information
	if !DllCall("GetFileInformationByHandle"
		, "Ptr", handle ; hFile
		, "Ptr", info) ; lpFileInformation
		return (DllCall("CloseHandle", "Ptr", handle), 0)
	; MsgBox "GetFileInformationByHandle failed " A_LastError
	
	high := NumGet(info, 44, "UInt") ; nFileIndexHigh
	low := NumGet(info, 48, "UInt") ; nFileIndexLow
	; MsgBox NumGet(info, 28, "UInt") ; dwVolumeSerialNumber
	
	if outhandle is VarRef
		%outhandle% := handle
	else
		DllCall("CloseHandle", "Ptr", handle)
	
	return 1
}

; Returns string on success or 0 on failure.
FileIdToPath(hint, high, low, outhandle := 0)
{
	static fileid := (() => (NumPut("UInt", 24, "UInt", 0, buf := Buffer(24)), buf))(), nameinfo := Buffer(520)
	
	NumPut("UInt", low, "UInt", high, fileid, 8)
	
	; The endianness of the file ID and whether hVolumeHint is necessary were figured out by trial and error.
	; https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-openfilebyid?redirectedfrom=MSDN
	; This unfortunate bastard requires an open file handle on the same volume.
	; It also allows opening a file with just the 64-bit file ID???
	handle := DllCall("OpenFileById"
		, "Ptr", hint ; hVolumeHint
		, "Ptr", fileid ; lpFileId
		, "UInt", 0 ; dwDesiredAccess
		, "UInt", 7 ; dwShareMode
		, "Ptr", 0 ; lpSecurityAttributes
		, "UInt", 0) ; dwFlagsAndAttributes
	
	if handle == -1
		return 0
	
	; https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getfileinformationbyhandleex
	if !DllCall("GetFileInformationByHandleEx"
		, "Ptr", handle ; hFile
		, "UInt", 2 ; FileInformationClass: FILE_NAME_INFO
		, "Ptr", nameinfo ; lpFileInformation
		, "UInt", nameinfo.Size) ; dwBufferSize
		return (DllCall("CloseHandle", "Ptr", handle), 0)
	
	if outhandle is VarRef
		%outhandle% := handle
	else
		DllCall("CloseHandle", "Ptr", handle)
	
	; That hex number is C: in UTF-16 (4 bytes, same as an Int)
	; We're replacing the first two bytes of this buffer with valid text and then interpreting the whole buffer as a string
	; I kinda sorta accidentally happened upon this because I couldn't be bothered to copy the string after the length to a new buffer
	; length >> 1 is because it just works, okay? Does the API really put the length in bytes, not in wchars there?
	length := NumGet(nameinfo, 0, "UInt")
	NumPut("UInt", 0x003a0043, nameinfo)
	return StrGet(nameinfo, (length >> 1) + 2, "UTF-16")
}
