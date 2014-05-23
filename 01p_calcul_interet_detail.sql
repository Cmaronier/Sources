                                              -- Calcul des intérêts
If Exists (Select 1 From sysobjects  Where type = 'P' and Lower(name) = Lower('p_calcul_interet_detail') ) 
	Drop Procedure p_calcul_interet_detail
go 

CREATE PROCEDURE p_calcul_interet_detail	@an_exrc	numeric(4)
AS
BEGIN
	DECLARE		@taux				Decimal(15,12),
				@ldt_ExrcDebut		Datetime,
				@ldt_ExrcFin		Datetime,
				@dt_movt			Datetime,
				@dt_entree			Datetime,
				@dt_sortie			Datetime,
				@dt_debut			Datetime,
				@dt_fin				Datetime,
				@nb_jour			Numeric(8),
				@id_unit			Numeric(15),
				@id_session			Numeric(15),
				@id_movt			Numeric(15),
				@fg_movt			Varchar(2),
				@fg_unit			Char(1),
				@mt_base			Decimal(17,5),
				@mt_interet			Decimal(17,5),
				@lb_dossier			varchar(20),
				@lb_message			varchar(255)
				
	-- Initilisation
	SELECT	@ldt_ExrcDebut = Convert( datetime, '01/01/' + convert(varchar(4), @an_exrc ), 103 ),
			@ldt_ExrcFin = Convert( datetime, '31/12/' + convert(varchar(4), @an_exrc ), 103 )
			
	/* Remi
  SELECT  @id_session = kpid
	FROM master..sysprocesses
	WHERE spid = @@spid*/
	exec p_get_session @id_session output
  	
	-- Recherche la valeur du taux pour l'année d'execice courante.
	SELECT	@taux =	Round( exrc.pc_tx_exrc / 100 , 12)
	FROM	exrc
	WHERE	nb_an_exrc = @an_exrc
	
	SELECT	@taux = IsNull( @taux, 0 )
	
	-- Curseur des versements sur lesquels on effectue le calcul des intérêts
	-- (Acquisition, Retro et préfinancement principal)
	DECLARE	curs_temp_unit_movt CURSOR FOR
		SELECT	id_unit, fg_unit, id_movt, fg_movt, mt_base, dt_movt, dt_entree, dt_sortie
		FROM	temp_unit_movt
		WHERE 	dt_movt <= @ldt_ExrcFin AND
				id_session = @id_session AND
				fg_movt IN ('A', 'R', 'PP' )
		for update

	OPEN curs_temp_unit_movt
	FETCH curs_temp_unit_movt INTO @id_unit, @fg_unit, @id_movt, @fg_movt, @mt_base, @dt_movt, @dt_entree, @dt_sortie
	
	WHILE (@@SqlStatus = 0)
	BEGIN


		-- Date de début des calculs des intêrets
		SELECT @dt_debut = CASE	
					WHEN (@dt_movt < @ldt_ExrcDebut AND @dt_entree < @ldt_ExrcDebut ) THEN @ldt_ExrcDebut
					WHEN (@dt_movt < @ldt_ExrcDebut AND @dt_entree >= @ldt_ExrcDebut ) THEN @dt_entree
					WHEN (@dt_movt >= @ldt_ExrcDebut AND @dt_movt < @dt_entree ) THEN @dt_entree
					ELSE @dt_movt
	 			   END,
			@dt_fin	=	CASE WHEN @dt_sortie <= @ldt_ExrcFin THEN @dt_sortie ELSE @ldt_ExrcFin END
		if @@error !=0 return

				
		SELECT	@nb_jour = CASE WHEN DatedIff(Day,@dt_debut,@dt_fin) + 1 > 365 
								THEN 365 
								ELSE DatedIff(Day,@dt_debut,@dt_fin) + 1 
							END
		if @@error !=0 return	
		/*
		IF @dt_fin < @dt_debut 
		BEGIN
			PRINT '@id_unit %1!, @fg_unit %2!, @id_movt %3!, @fg_movt %4!, @mt_base %5!, @dt_movt %6!, @dt_entree %7!, @dt_sortie %8!', @id_unit, @fg_unit, @id_movt, @fg_movt, @mt_base, @dt_movt, @dt_entree, @dt_sortie
			PRINT '@dt_debut %1!, @dt_fin %2!, @nb_jour %3!', @dt_debut , @dt_fin, @nb_jour
			IF @fg_unit = 'P'
				SELECT @lb_dossier = acqui.cd_codf_lett + ' ' + acqui.cd_codf_dept + ' ' + 
						right(acqui.cd_codf_an,2) + ' '  + acqui.cd_codf_doss + ' ' + acqui.cd_codf_cptr
				FROM 	unit_acqui_fncr
						INNER JOIN acqui ON (unit_acqui_fncr.id_acqui = acqui.id_acqui)
				WHERE	unit_acqui_fncr.id_unit_acqui_fncr = @id_unit
			ELSE
				SELECT @lb_dossier = acqui.cd_codf_lett + ' ' + acqui.cd_codf_dept + ' ' + 
						right(acqui.cd_codf_an,2) + ' '  + acqui.cd_codf_doss + ' ' + acqui.cd_codf_cptr
				FROM 	acqui_nonfncr
						INNER JOIN acqui ON (acqui_nonfncr.id_acqui = acqui.id_acqui)
				WHERE	acqui_nonfncr.id_unit_non_fncr = @id_unit

			SELECT @lb_message = 'Problème sur le dossier : ' + @lb_dossier + '. Vérifiez les dates du dossier et les versements.' +
					' Vérifiez aussi la rétrocession le cas échéant.'
					
			RAISERROR 98000 @lb_message
			RETURN
		END
*/

		IF @dt_fin < @dt_debut 
		BEGIN
			SELECT	@nb_jour = 0
		END

		SELECT	@mt_interet = Isnull(Round( @mt_base * @taux * @nb_jour / 365, 5), 0)
		if @@error !=0 return

		UPDATE temp_unit_movt
		SET dt_deb_calcul = @dt_debut,
			dt_fin_calcul = @dt_fin,
			nb_jour = @nb_jour
		WHERE id_unit = @id_unit AND fg_unit = @fg_unit AND id_session = @id_session AND id_movt = @id_movt AND fg_movt = @fg_movt
		if @@error !=0 return

		-- Mise à jour du montant des intérêts dans la table temporaire
		-- Si la date de sortie correspond à l'année courante, on place les intérêts 
		-- dans la colonne is_exrc
		IF @dt_sortie BETWEEN @ldt_ExrcDebut AND @ldt_ExrcFin
		BEGIN
			UPDATE temp_unit_movt
			SET mt_is_exrc = CASE WHEN fg_movt IN ( 'R', 'PP') THEN -1 * @mt_interet ELSE @mt_interet END
			WHERE id_unit = @id_unit AND fg_unit = @fg_unit AND id_session = @id_session AND id_movt = @id_movt AND fg_movt = @fg_movt
		END
		ELSE
		BEGIN
			UPDATE temp_unit_movt
			SET mt_is_prec = mt_is_prec + CASE WHEN fg_movt IN ( 'R', 'PP') THEN -1 * @mt_interet ELSE @mt_interet END
			WHERE id_unit = @id_unit AND fg_unit = @fg_unit AND id_session = @id_session AND id_movt = @id_movt AND fg_movt = @fg_movt
		END
		if @@error !=0 return
		-- Versement suivant
		FETCH curs_temp_unit_movt INTO @id_unit, @fg_unit, @id_movt, @fg_movt, @mt_base, @dt_movt, @dt_entree, @dt_sortie
	END
	
	CLOSE curs_temp_unit_movt
	DEALLOCATE CURSOR curs_temp_unit_movt
	
	-- ON ne calcul pas les intérêt sur l'année précédante, on va les chercher sur le stock.
	/*
	IF EXISTS ( SELECT 1 FROM #marge_vrst WHERE dt_vrst < @ldt_ExrcDebut )
	BEGIN
		-- Récursivité (calcul des intérets sur les années précédante)
		SELECT @an_exrc = @an_exrc - 1
		EXEC p_calcul_interet_detail @an_exrc
	END
	*/
END
go

grant execute on p_calcul_interet_detail to public
go 
