.286		; pusha, popa 

buf_size equ 1000d		; stala 

data segment
	
	no_args			db      "Blad: nie podano argumentow.$"
	not_en 			db 		"Blad: podano za malo argumentow. Odpowiednia ilosc: 2.$"	
	too_many		db 		"Blad: podano za duzo argumentow. Odpowiednia ilosc: 2.$"
	v0_info			db		"Weryfikacja, czy plik wejsciowy zawiera poprawne znaki:$"
	v0_alert1		db		13, 10, "Napotkano bledny znak. $"		; 13, 10 - CRLF
	v0_alert2		db		13, 10, "Linia: $"
	num_of_line		dw		1h										; v0 - numer linii z blednym znakiem
	v0_alert3		db		13, 10, "Numer znaku w linii: $"
	num_in_line		dw		0h										; v0 - numer blednego znaku w linii 
	v0_ok			db		13, 10, "Nie napotkano zadnych bledow podczas sprawdzania. Plik wejsciowy sklada sie z poprawnych znakow.$"
	v1_info			db		"Wypisywanie statystyk do pliku wyjsciowego.$"
	v1_exists		db		13, 10, "Podany plik wynikowy juz istnieje. Zostal on nadpisany nowa zawartoscia.$"
	txt			db		" >>> STATYSTYKA PLIKU WEJSCIOWEGO $"
	txt_2			db		" <<<"
	txt_wsp			db		13, 10, "Liczba bialych znakow: $"
	txt_lns			db		13, 10, "Liczba linii: $"
	txt_pns			db		13, 10, "Liczba znakow interpunkcyjnych: $"
	txt_digs		db		13, 10, "Liczba cyfr: $"
	txt_let			db		13, 10, "Liczba liter: $"
	txt_words		db		13, 10, "Liczba wyrazow: $"
	txt_sen			db		13, 10, "Liczba zdan: $"
	failed_opening		db		13, 10, "Blad: nie udalo sie otworzyc pliku.$"
	failed_creating		db		13, 10, "Blad: nie udalo sie utworzyc pliku o podanej nazwie.$"
	failed_reading		db		"Blad: odczyt z pliku nie powiodl sie.$"
	;pomocy			dw		2324d
	
	; v1 - liczniki 
	whitespaces		dw		0d							; liczba bialych znakow - spacja/tabulator 
	lines			dw		1d							; liczba linii
	punctmarks		dw		0d							; liczba znakow interpunkcyjnych
	cyphers			dw		0d							; liczba cyfr
	letters			dw		0d							; liczba liter
	words			dw		0d							; liczba wyrazow
	sentences		dw		0d							; liczba zdan
	
	
	buf				db 		150 dup (0)				; tablica na dane wejsciowe, maks 150 znakow parametrow
	num_of_args 	db		0h						; liczba wprowadzonych argumentow
	which_vers		db		?						; zmienna-flaga - ktora wersje programu realizujemy 
	input_file		dw		?						
	output_file		dw		?
	finish			db		0h						; flaga ustawiana przez get_char - czy przeczytalismy juz caly plik 
	num_string		db		6 dup (0), '$'			; bufor na liczbe zmieniana w stringa przez number_to_str
	buffer			db		buf_size dup (?)
	read_chars		dw		?
	chars			db		20h, 22h, 9h, 0dh, ".,!?'()[]{}<>:;-0" ; v0 - mozliwe znaki interpunkcyjne, spacje, tabulatory i znaki nowej linii 
	punct_marks		db		".?!,:;-()[]{}", 22h, "<>'0"	; v1 - znaki interpunkcyjne 
	
	args_offsets		db 		20 dup (?)					; tablice: offsetow, dlugosci argumentow									
	args_lengths		db 		20 dup (?)														
	input_bytes 		db 		0h							; liczba bajtow wprowadzonych w linii komend		
	
data ends


code segment

	start:
		assume cs:code, ds:data, ss:sstack 
		
		mov ax,seg stack_ptr							; przygotowanie stosu
		mov ss,ax		
		mov sp,offset stack_ptr	

		mov ax, seg data								; bohater mojego parsera!
		mov ds, ax
		
		call read										; wywolanie funkcji
		call check_args
		call main
		call end_of_prog

; ===== PARSER =====

	; ===== 1. WCZYTAJ ARGUMENTY =====
    ; pobiera znaki z linii komend, sprawdza czy bialy i zjada biale, reszte zapisuje w tabicy argumentow 'buf', jesli brak argumentow -> alert, 
	; zlicza argumenty -> num_of_args, wypelnia tablice offsetow paczatkow (pierwszych znakow) argumentow (args_offsets) oraz tablice dlugosci argumentow (args_lengths)
	read proc	
		pusha							; odkladam dotychczasowe wartosci rejestrow na stosie, aby ich nie utracic (przy .286 mozna tez pusha i popa, wtedy jeszcze sp i bp)

		xor ax, ax							; czyszcze rejestry, ktore za chwile wykorzystam
		xor bx, bx
		xor cx, cx
		xor di,di																
		xor si,si																															
	
		mov bl, byte ptr es:[80h]			; do bl kopiuje liczbe znakow w linii komend - 80h (ile znakow podalismy w linii kodu)
											; 81h (spacje), 82h (od niego kolejno wprowadzone argumenty)
		cmp bl, 1h																
		jb alert_no_args					; jesli mamy mniej niz 1 znak, to nie podano argumentow -> komunikat i wyjscie										
	
		; wpp -> przechwytujemy argumnty do przygotowanej tablicy
		
		mov si, offset buf					; ustawiam offset na tablice na argumenty (=lea si,buf - mniej optymalne, do obliczen!), znak -> si								
		mov cx, offset args_offsets			; umieszczam w cx offset tablicy offsetow argumentow 
		
		dec bx								; bx - liczba bajtown/znakow z linii komend
											; dekrementuje, by pominac spacje pod offsetem 81h
		mov word ptr ds:[input_bytes], bx	; otrzymana liczbe bajtow zapisuje do przygotowanej zmiennej 										

		mov al, byte ptr es:[82h]			; pierwszy znak z linii komend -> al											
		call check_if_white					; sprawdz, czy jest bialym znakiem							
		cmp ah, 0h							; flaga: 0=nie bialy, 1=bialy -> trzeba go zjesc
		je get_the_char						; jesli znak nie jest bialy, przetwarzamy go 
		; jne -> zjedz bialy znak
		
		eat:								; dla bialego znaku
			call eat_it								; lec po bialych znakach dopoki nie napotkasz nie bialego, di - licznik sprawdzonych znakow 								
			cmp di, word ptr ds:[input_bytes]		; czy sprawdzilismy juz wszystkie wprowadzone znaki?										
			je finish_parsing						; jesli tak, konczymy 
			
		get_the_char:						; dla pierwszego nie bialego znaku po bialych (pierwszego znaku nowego argumentu)									
			push bx
			push dx
			push di																		
			push ax
			
			mov di, cx							; teraz di -  wskaznik kolejnego wolnego miejsca w tablicy offsetow																			
			mov word ptr ds:[di], si			; zapisz offset tego argumentu w tablicy offsetow 										
			add cx, 2h							; przy kolejnym wywolaniu zwieksz wskaznik tablicy args_offsets o 16 bitow, czyli dlugosc kolejnego offsetu 												
			inc num_of_args						; inkrementuj liczbe argumentow 								
			xor dl, dl							; wyzeruj licznik dlugosci argumentu, bo bedziemy go przegladac 									
				
			pop ax																		
			pop di
				
			characters:								; przetwarzaj nowy argument 
				mov byte ptr ds:[si], al			; zapisz nie bialy znak do tablicy argumentow 								
				inc dl								; dl - licznik dlugosci aktualnego argumentu - zwiekszamy 									
				inc di								; di - licznik znakow z linii komend - zwiekszamy (przeskocz na kolejny znak z linii komend)				
				cmp di, word ptr ds:[input_bytes]	; czy sprawdzilismy juz wszystkie wprowadzone znaki?																
				je fin								; jesli tak, konczymy 									
					
				inc si								; wpp -> przesuwamy wskaznik w tablicy argumentow													
				mov al, byte ptr es:[82h + di]		; pobierz kolejny znak z linii komend									
				xor ah, ah							; zerujemy ah -> flaga
				call check_if_white														
				cmp ah, 0h							; jesli kolejny znak nie jest bialy, dalej iterujemy po argumencie 									
			je characters																
			; wpp (koniec argumentu):
			
			fin:	
				push di																	
				inc si								; przesun wskaznik w tablicy argumentow - rozdzielamy argumenty dolarami																
				mov di, offset args_lengths									
				mov ax, word ptr ds:[num_of_args]	; numer ostatniego argumentu -> ax																									
				add di, ax		
				dec di								; di wskazywal wczesniej na 1. argument 
				mov byte ptr ds:[di], dl			; zapisz dlugosc ostatniego argumentu								
				pop di
				pop dx
				pop bx	
				cmp di, word ptr ds:[input_bytes]	; czy sprawdzilismy juz wszystkie wprowadzone znaki?																
		jne eat										; jesli nie, jedz biale znaki dopoki nie trafisz na kolejny arg 							
			
		jmp finish_parsing
		
		check_if_white proc				; otrzymuje znak w al, sprawdzam, czy znak jest bialy 
			xor ah, ah					; zeruje, w ah ustawie za chwile flage - 1=bialy, 0=nie bialy
			cmp al, 20h					; 20h - spacja w tabeli ASCII									
			je white																		
			cmp al, 9h					; 9h - tabulator w tabeli ASCII												
			je white															
			ret		
			
			white:
				mov ah, 1h		; ustawiam flage														
				ret
		check_if_white endp
		
		eat_it proc						; otrzymuje w di licznik sprawdzonych znakow 																				
			push bx
			
			its_white:
				inc di								; inkrementujemy liczbe sprawdzonych znakow (bialy, wiec pomijamy) 															
				cmp di, word ptr ds:[input_bytes]	; czy sprawdzilismy juz wszystkie wprowadzone znaki?													
				je exit								; jesli tak, konczymy 							
				mov al, byte ptr es:[82h + di]		; wpp: pobieramy do akumulatora nastepny znak z linii komend					
				xor ah, ah							; zerujemy ah -> ustawimy flage			
				call check_if_white															
				cmp ah, 1h															
			je its_white							; jesli bialy, jedz dalej, dopoki nie napotkasz nie bialego 
			
			exit:
			pop bx
			ret
		eat_it endp
		
		alert_no_args:
			mov ax, seg no_args
			mov ds, ax
			mov dx, offset no_args
			mov ah, 9h							; funkcja int 21,9 wypisuje odpowiedni komunikat z ds:dx, konczymy
			int 21h
			popa
			call end_of_prog
			
			finish_parsing:
				popa				; przywracam pierwotne wartosci rejestrow
				ret
		
	read endp

	; ===== 2. SPRAWDZ POPRAWNOSC ARGUMENTOW =====
	; sprawdza poprawnosc wprowadzonych danych - czy podano dokladnie 2 argumenty, czy pierwszy z nich to '-v', w zmiennej 'which_vers' zapisuje, ktora wersje programu bedziemy realizowac:
	; 0 - nazwa_programu -v input
	; 1 - nazwa_programu input output
	check_args proc			
		push di				; odkladam dotychczasowe wartosci rejestrow na stosie, aby ich nie utracic
		push si	
		push bx
		push cx
		push dx
		
		; czy wprowadzono prawidlowa liczbe argumentow?
		mov al, num_of_args
		cmp al, 2h																									
		jb not_enough			; jesli mniej niz 2, to za malo
		ja tumany				; jesli wiecej niz 2, to za duzo
			
		; czy argument 1. to -v?											
		mov si, offset args_offsets														
		mov di, word ptr ds:[si]											
		mov al, byte ptr ds:[di]									
		cmp al, '-'											
		jne version1					
		;mov di, word ptr ds:[si]		
		inc di 
		mov al, byte ptr ds:[di]								
		cmp al, 'v'					
		jne version1	
		mov di, offset args_lengths														
		mov ah, byte ptr ds:[di]		; dlugosc 1. parametru -> ah													
		cmp ah, 2d																
		jne version1					; jesli rozna od 2, to nie mamy do czynienia z postacia "nazwa_programu -v input"
		jmp version0
		
			not_enough:					; komunikat gdy za malo arg.
				mov ax, seg not_en
				mov ds, ax
				mov dx, offset not_en
				jmp alert_exit
			
			tumany:						; komunikat gdy za duzo arg.
				mov ax, seg too_many
				mov ds, ax
				mov dx, offset too_many
				jmp alert_exit
				
			version0:
				mov ds:[which_vers], 0d
				mov ax, seg v0_info
				mov ds, ax
				mov dx, offset v0_info
				jmp message

			version1:
				mov ds:[which_vers], 1d
				mov ax, seg v1_info
				mov ds, ax
				mov dx, offset v1_info
				jmp message
				
			message:																			
				mov ah, 9h																
				int 21h																	
				jmp exit
				
			alert_exit:					; wypisz komunikat i zakoncz 															
				mov ah, 9h																
				int 21h																	
				call end_of_prog	

		exit:
		pop dx							; przywracam pierwotne wartosci rejestrow
		pop cx
		pop bx
		pop si
		pop di
		ret
	check_args endp
	
	; ===== 3. GLOWNA FUNKCJA STERUJACA DZIALANIEM PROGRAMU =====
	; w zaleznosci od wartosci w zmiennej 'which_vers', przelacza na odpowiednia wersje programu
	main proc
		pusha
	
		cmp ds:[which_vers], 0d
		je m_version0
		
		m_version1:
			call statistics
			;call lipa			; koryguje wyniki statystyk ("magicznie" wszystko * 2) 
			call fill_output
			mov bx, input_file	; zamknij wykorzystywane pliki 
			call close_file
			mov bx, output_file
			call close_file
			jmp exit
		m_version0:
			call verify
			mov bx, input_file
			call close_file
			jmp exit
	
		exit:
			popa
			ret
	main endp
	
	; ===== 4. WERSJA 0 - WERYFIKACJA =====
	; sprawdza, czy plik wejsciowy zawiera jedynie znaki alfanumeryczne, interpunkcyjne, spacje, tabulatory i znaki nowej linii 
	; jesli tak nie jest -> komunikat zawierajacy numer linii i niewlasciwego znaku w linii
	verify proc
		pusha
		
		mov al, 1d			; flaga dla funkcji open_file - otworz plik podany jako 2. argument i mianuj go input file
		call open_file
		
		mov bx, ds:[input_file]		; ODCZYT Z PLIKU: bx = uchwyt pliku odczytywanego
		
		verify_file:
			call get_char			; wczytaj partie pliku do bufora
			call check				; sprawdz te partie pliku 
			cmp ds:[finish], 1d		; czy przeczytano juz caly plik?
		jne verify_file
		
		exit:
			popa
			ret
	verify endp
	
	check proc			; sprawdza partie znakow wczytana do bufora w get_char 
		pusha
		
		mov cx, word ptr ds:[read_chars]		; cx - tyle znakow udalo sie pobrac do bufora w tej partii 
		xor bx, bx								; bx - 'przesuwa sie' po kolejnych znakach bufora 
		
		verif:							; petla sprawdzajaca, czy znaki sa wlasciwe 
			inc ds:[num_in_line]	; zwieksz numer znaku w linii o 1 (zaczynamy od 0)
			mov al, byte ptr ds:[buffer+bx]		; kolejny znak z bufora -> al 
			cmp al, 10d
			je new_line
			cmp al, 7bh	; 7bh = '{' w ASCII table
			jae punctuation
			cmp al, 61h	; 61h = 'a' 
			jae alphanumeric
			cmp al, 5bh	; 5bh = '['
			jae punctuation
			cmp al, 41h	; 41h = 'A'
			jae alphanumeric
			cmp al, 3ah	; 3ah = ':'
			jae punctuation
			cmp al, 30h	; 30h = '0'
			jae alphanumeric
			
			punctuation:
				push cx
				mov cx, 21d 		; tyle mamy roznych mozliwych znakow interpunkcyjnych (wypisanych w tabeli 'chars')
				push bx
				xor bx, bx			; bx - 'przesuwa sie' po kolejnych znakach w tabeli 'chars'
				
				compare:
					cmp al, ds:[chars+bx]	; czy nasz znak z bufora == znak z tabeli 'chars'?
					je jump_out				; jesli tak, ok -> wyskakujemy 
					inc bx					
				loop compare
				
				jump_out:					; jesli doszlismy do konca petli i nie napotkalismy ts znakow
					cmp bx, 21d				; to plik zawiera nie tylko znaki alfanumeryczne 
					je wrong_char
				
				pop bx
				pop cx	
				jmp alphanumeric
				
			new_line:
				inc ds:[num_of_line]		; zwieksz numer linii o 1 (zaczynamy od 1)
				mov ds:[num_in_line], 0d	; wyzeruj licznik w linii 
				jmp alphanumeric

			alphanumeric:			; jesli alfanumeryczny, to ok -> lecimy dalej 
				inc bx	
		loop verif 
		
		mov ax, seg v0_ok			; jesli wszystkie znaki sprawdzone w petli byly poprawne
		mov ds, ax					; -> wypisujemy pozytywny komunikat 
		mov dx, offset v0_ok
		mov ah, 9h
		int 21h
		jmp exit
		
		wrong_char:					; napotkano niepoprawny znak -> alert 
			mov ax, seg v0_alert1
			mov ds, ax
			mov dx, offset v0_alert1
			mov ah, 9h
			int 21h
			
			mov dx, offset v0_alert2
			mov ah, 9h
			int 21h
			mov ax, word ptr ds:[num_of_line]
			call number_to_str				; 'przepisz' liczbe calkowita do stringa i wypisz ja 
			
			mov dx, offset v0_alert3
			mov ah, 9h
			int 21h
			mov ax, word ptr ds:[num_in_line]
			call number_to_str				; 'przepisz' liczbe calkowita do stringa i wypisz ja 
			call end_of_prog
			
		exit:
			popa
			ret
	check endp
	
	; ===== 5. WERSJA 1 - STATYSTYKA PLIKU TEKSTOWEGO =====
	; opracowuje proste statystyki dotyczace pliku wejsciowego: liczbe bialych znakow, liczbe znakow interpunkcyjnych, liczbe cyfr, liter, wyrazow,
	; zdan, linii i zapisuje je do pliku wyjsciowego 
	statistics proc
		pusha
		
		mov al, 2d 				; flaga - otworz plik podany jako 1. argument i mianuj go input file
		call open_file
		
		mov al, 3d				; flaga - utworz plik podany jako 2. argument i mianuj go output file
		call open_file
		
		mov bx, ds:[input_file]	; bx - uchwyt pliku do otwarcia 
		
		count_all:
			call get_char
			call count
			cmp ds:[finish], 1d	; czy przeliczono juz wszystkie znaki z pliku wejsciowego?
		jne count_all
		
		popa
		ret 
	statistics endp
	
	count proc		; przebiega po kolei znaki z bufora i sprawdza, jaki to znak, nastepnie inkrementuje odpowiedni licznik
		pusha
		
		mov cx, word ptr ds:[read_chars]	; cx - ile znakow udalo sie wczytac do bufora
		xor bx, bx						; bx - 'przesuwa sie' po kolejnych znakach bufora 
		
		thru_buffer:			; petla przechodzaca przez znaki z bufora 
			xor ax, ax
			mov ah, byte ptr ds:[buffer+bx]		; ah <- kolejny znak z bufora 
			; sprawdzmy, co to za znak:
			cmp ah, 9h				; 9h = tab w kodzie ASCII
			je its_whitespace
			cmp ah, 20h				; 32d = 20h = spacja w kodzie ASCII
			je its_whitespace
			push ax
			call check_punctmark	; sprawdz, czy jest znakiem interpunkcyjnym 
			pop ax 
			xor al, al 
			cmp ah, 30h				; 30h = 48d = '0' w ASCII
			jae cypher_maybe
			back:
			call check_letter	; sprawdz, czy jest litera 
				cmp al, 1d
				je its_letter
			call check_newline		; sprawdz, czy jest znakiem nowej linii 
			
			jmp continue
				
			its_letter:
				inc ds:[letters]
				jmp continue	
				
			cypher_maybe:
				cmp ah, 39h			; 39h = 57d = '9' w ASCII
				jbe its_cypher			
				jmp back 
				
			its_cypher:
				inc ds:[cyphers]
				jmp continue
				
			its_punctmark:
				inc ds:[punctmarks]
				jmp continue
			
			its_whitespace:
				inc ds:[whitespaces]
				cmp bx, 0h
				je continue
				call check_word_end		; sprawdz, czy poprzedni znak byl litera, czyli koncem slowa 
				;jmp continue
				
			continue:
			inc bx
		loop thru_buffer
	
		popa
		ret
	count endp
	
	check_punctmark proc
		push cx
		push dx
		push bx
		
		xor bx, bx		; bx - 'biegnie' po naszej tablicy 'punct_marks'
		
		compare:
			mov al, ds:[punct_marks+bx]		; al - kojejny mozliwy znak interpunkcyjny 
			cmp ah, al
			je hitnsunk						; jesli kolejny znak z bufora == al, to trafilismy na znak interpunkcyjny 
			inc bx
			cmp ds:[punct_marks+bx], '0'	; czy doszlismy juz do konca tablicy 'punct_marks'?
			je exit							; jesli tak, wyskakujemy 
		jne compare	
			
		hitnsunk:					; trafilismy na znak interpunkcyjny 
			inc ds:[punctmarks]
			cmp bx, 2d				; czy nasz znak jest ". ? !" ?
			ja end_of_word			; jesli nie, sprawdzamy, czy przed nim skonczylo sie slowo 
			pop bx
			mov ah, ds:[buffer+bx-1]
			push bx
			xor al, al
			call check_letter 	; sprawdzamy, czy znak przed ". ? !" byl litera 
			cmp al, 1d
			jne exit			; jesli nie byl, nie zwiekszamy liczby zdan 
			inc ds:[sentences]
			
			end_of_word:
			pop bx
			call check_word_end
			push bx
		
		exit:
		pop bx
		pop dx
		pop cx
		ret
	check_punctmark endp
	
	check_word_end proc
		push ax
		
		dec bx
		mov ah, ds:[buffer+bx]	; ah - znak tuz przed aktualnie badanym znakiem interpunkcyjnym z bufora 
		xor al, al
		call check_letter
		inc bx
		cmp al, 0d				
		je exit				; jesli nie byl litera, nie zwiekszamy liczby slow 
		inc ds:[words]
		
		exit:
			pop ax	
			ret
	check_word_end endp
	
	check_letter proc
		cmp ah, 41h		; 41h = 65d = 'A' w kodzie ASCII
		jb exit
		cmp ah, 5ah		; 5ah = 90d = 'Z' w kodzie ASCII
		jbe letter
		cmp ah, 7ah		; 7ah = 122d = 'z' w kodzie ASCII
		ja exit
		cmp ah, 61h 	; 61h = 97d = 'a' w kodzie ASCII 
		jae letter
		
		letter:
			mov al, 1d		; jest litera -> ustaw flage 
		
		exit:
			ret
	check_letter endp
	
	check_newline proc
		xor al, al
		cmp ah, 10d			; 10d - kod LF (nowej linii) w ASCII 
		jne exit

		inc ds:[lines]		; jesli ah == 10d, to inkrementujemy liczbe linii 
		cmp bx, 1h			; pierwsza linia 
		je exit

		mov ah, byte ptr ds:[buffer+bx-2]		; cofamy sie o 2 znaki do tylu = 13, 10 (CRLF) 

		call check_letter		; czy 2 znaki wczesniej byla litera?
			cmp al, 1d
			je was_a_word		; jesli byla, to byl to koniec slowa 
			jmp exit
			
		was_a_word:
			inc ds:[words]		
		
		exit:			
			ret
	check_newline endp
	
	save proc
		pusha
									; zapisywanie do pliku: ds:dx - adres bufora zawierajacego dane do zapisu
									; cx - dlugosc zapisywanego aktualnie bufora do pliku wyjsciowego 
		mov bx, word ptr ds:[output_file]	; bx - uchwyt pliku do zapisu 
		mov ah, 40h			; ah = 40h - zapisywanie do pliku zaczynajac od aktualnej pozycji wskaznika w pliku 
		int 21h
		
		popa
		ret
	save endp
	
	fill_output proc			; korzystajac z funkcji save oraz number_to_str, wypelnia danymi plik wynikowy 
		pusha
		; komunikat w 1. linii pliku 
		mov dx, offset txt		; zapisywanie do pliku: ds:dx - adres bufora zawierajacego dane do zapisu
		mov cx, 34d
		call save
		
		xor cx, cx  
		; wypisz nazwe pliku wejsciowego, dla ktorego utworzono statystyki 
		mov si, word ptr offset args_offsets	
		mov dx, word ptr ds:[si]
		mov di, offset args_lengths
		mov cl, byte ptr ds:[di]
		call save
		
		mov dx, offset txt_2
		mov cx, 4d
		call save
		
		mov dx, offset txt_wsp		; wypisz tekst - liczba linii 
		mov cx, 25d
		call save
		
		mov dx, 1d					; dx - flaga dla funkcji number_to_str - v0: wypisz na ekran, v1: zapisz do pliku 
		mov ax, word ptr ds:[whitespaces]
		call number_to_str
		
		mov dx, offset txt_lns
		mov cx, 16d
		call save
		
		mov dx, 1d
		mov ax, word ptr ds:[lines]
		call number_to_str
		
		mov dx, offset txt_pns
		mov cx, 34d
		call save
		
		mov dx, 1d
		mov ax, word ptr ds:[punctmarks]
		call number_to_str
		
		mov dx, offset txt_digs
		mov cx, 15d
		call save
		
		mov dx, 1d
		mov ax, word ptr ds:[cyphers]
		call number_to_str
		
		mov dx, offset txt_let
		mov cx, 16d
		call save
		
		mov dx, 1d
		mov ax, word ptr ds:[letters]
		call number_to_str
		
		mov dx, offset txt_words
		mov cx, 18d
		call save
		
		mov dx, 1d
		mov ax, word ptr ds:[words]
		call number_to_str
		
		mov dx, offset txt_sen
		mov cx, 15d
		call save
		
		mov dx, 1d
		mov ax, word ptr ds:[sentences]
		call number_to_str
		
		popa
		ret
	fill_output endp
	
	; ===== 6. FUNKCJE WSPOLNE DLA OBU WERSJI =====
	; === 6a. Otworz plik - w zaleznosci od ustawionej w al flagi podejmuje probe otwarcia / utworzenia okreslonego pliku
	; ustawia 'input_file' i 'output_file', jesli nie udalo sie otworzyc/utworzyc -> komunikat o bledzie
	open_file proc
		pusha
		
		cmp al, 1d
		je o_version0			; drugi argument = input_file
		cmp al, 2d
		je o_version1_first		; pierwszy argument = input_file
		cmp al, 3d
		je o_version1_second	; drugi argument = output_file
		
		o_version0:
			mov si, word ptr offset args_offsets														
			mov dx, word ptr ds:[si+2]	; offset 2. arg. -> dx
			
			xor al, al		; al = 0 -> tylko do odczytu
			mov ah, 3dh
			int 21h
			jc open_sth_went_wrong	; jesli cf jest ustawiona, to nastapil blad otwarcia
			; jesli cf nie jest ustawiona, operacja przebiegla pomyslnie i ax zawiera uchwyt pliku:
			mov ds:[input_file], ax ; input_file = uchwyt pliku 		
			jmp exit
		
		o_version1_first:
			mov si, offset args_offsets														
			mov dx, word ptr ds:[si]	
			xor al, al			; al = 0 -> tylko do odczytu
			mov ah, 3dh
			int 21h
			jc open_sth_went_wrong
			mov ds:[input_file], ax
			jmp exit
			
		o_version1_second:
			mov si, word ptr offset args_offsets														
			mov dx, word ptr ds:[si+2]	; offset 2. arg. -> dx
			; czy plik wynikowy juz istnieje? - podejmij probe otwarcia pliku w trybie do odczytu 
			push ax
			xor al, al
			mov ah, 3dh
			int 21h
			jc skip			; jesli nie istnieje, cf = 1 (blad otwarcia)
				push dx
				mov dx, offset v1_exists 	; komunikat, ze istnieje 
				mov ah, 9h
				int 21h		
				pop dx
			skip:		; tworzymy/nadpisujemy nowy plik 
			pop ax
			xor cx, cx	; cx = 0 -> zaden z atrybutow pliku nie jest ustawiony 
			mov ah, 3ch
			int 21h
			jc create_sth_went_wrong
			; jesli nie doszlo do bledu, ax zawiera uchwyt pliku
			mov ds:[output_file], ax
			jmp exit
			
		open_sth_went_wrong:
			mov ax, seg failed_opening
			mov ds, ax
			mov dx, offset failed_opening
			mov ah, 9h
			int 21h
			call end_of_prog	

		create_sth_went_wrong:
			mov ax, seg failed_creating
			mov ds, ax
			mov dx, offset failed_creating
			mov ah, 9h
			int 21h
			call end_of_prog
		
		exit:
			popa
			ret
	open_file endp
	
	; === 6b. GetChar - wczytuje kolejne partie pliku do bufora 'buffer'
	get_char proc
		pusha
		
		mov cx, [buf_size]			; ODCZYT Z PLIKU: w bx mamy juz uchwyt pliku, ah = 3fh, cx = liczba bajtow do odczytania 
		mov dx, offset buffer		; ds:dx = adres bufora, do ktorego maja byc czytane dane z pliku 
		mov ah, 3fh
		int 21h
		jc	read_sth_went_wrong		; jesli cf = 1, to wystapil blad przy odczytywaniu z pliku 
		; jesli cf = 0, to operacja przebiegla pomyslnie
		
		mov ds:[read_chars], ax		; w ax jest ilosc przeczytanych bajtow - zapisuje, by wykorzystac w check/count 
		cmp ax, [buf_size]		
		jb all_read					; jesli ilosc przeczytanych bajtow < od ilosci, ktora mialo przeczytac, to przeczytalismy juz caly plik
		jmp exit
		
		read_sth_went_wrong:
			mov ax, seg failed_reading
			mov ds, ax
			mov dx, offset failed_reading
			mov ah, 9h
			int 21h
			call end_of_prog
		
		all_read:					; ustawiam flage, ze przeczytano juz caly plik 
			mov ds:[finish], 1d
		
		exit:
			popa
			ret
	get_char endp
	
	; === 6c. Liczba -> string - w ax dostaje liczbe calkowita do przekonwertowania, kolejne reszty z dzielenia przez 10 wpisuje do stringa 
	; a nastepnie wypisuje na ekran lub zapisuje do pliku nowopowstalego stringa 
	number_to_str proc
		push bx
		push cx
		push si
		push dx
		
		mov cx, 10d 	; cx - dzielnik 
		mov bx, 5d		; bx - wyznacza miejsca od prawej strony w naszej tablicy na cyfre 
		xor dx, dx
		xor si, si		; si - licznik dlugosci liczby (ile cyfr)
		
		convert:
			div cx			; ax = dx:ax / cx , reszta w dx (dl <= 256)
			mov ds:[num_string+bx], dl
			add ds:[num_string+bx], 30h		; 30h = '0', dzieki dodaniu kodu mamy kod cyfry w ASCII 
			inc si
			cmp ax, 0d						
			je convert_fin					; jesli ax == 0, to konczymy przepisywanie
			
			xor dx, dx
			dec bx							; przesuwamy sie o jedna cyfre 'w lewo' w naszym buforze-stringu na liczbe 
		jmp convert
		
		convert_fin:						
			mov cx, si		; w cx dlugosc liczby (korzysta z niej fill_output i save)
			pop dx
			cmp dx, 1d
			jne fin_v0
			je fin_v1
			
		fin_v0:
			mov dx, offset [num_string]		; wypisz liczbe-stringa 
			mov ah, 9h
			int 21h
			jmp exit
			
		fin_v1:
			mov dx, offset [num_string]		; zapisz liczbe-stringa do pliku wyjsciowego 
			add dx, bx
			;mov bx, dx
			call save
			
		exit:
			pop si
			pop cx
			pop bx 
			ret
	number_to_str endp
	
	close_file proc
		mov ah, 3eh
		int 21h
		ret
	close_file endp
	
	; lipa proc				; dzieli wszystkie wyniki przez 2
		; shr whitespaces, 1d
		; shr lines, 1d
		; inc lines			; zwieksz liczbe linii o 1 (pierwsza linia)
		; shr punctmarks, 1d
		; shr cyphers, 1d
		; shr letters, 1d
		; shr words, 1d
		; shr sentences, 1d
	; ret
	;lipa endp
	
		; ===== KONIEC PROGRAMU =====
		end_of_prog proc
			mov	ah, 4ch			; koniec, powrot do DOS - int 21,4c -> terminate process
			int	21h
			ret
		end_of_prog endp 

	code ends

sstack segment stack
	dw 150 dup (?)				; stos o rozmiarze 151 slow
	stack_ptr dw ?
sstack ends

end start
